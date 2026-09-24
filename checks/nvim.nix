# Headless Neovim checks (PD7). Neovim is the template configuration's
# `programs.nvf.finalPackage`; every run gets its own HOME and XDG dirs in
# the build directory. The process is named `.nvim-wrapped`.
{
  pkgs,
  lib,
  Ct,
}: let
  nvim = "${Ct.programs.nvf.finalPackage}/bin/nvim";

  # Shell helpers shared by the checks: `fresh <case>` makes the case's
  # directories and exports its environment; `bad <case> <msg>` records a
  # failure without stopping the run.
  prelude = ''
    set -uo pipefail
    fail=0
    bad() { echo "$1: $2" >&2; fail=1; }
    fresh() {
      local d=$TMPDIR/$1
      mkdir -p "$d/home" "$d/state/my-theme" "$d/data" "$d/cache" "$d/config"
      export HOME=$d/home XDG_STATE_HOME=$d/state XDG_DATA_HOME=$d/data \
        XDG_CACHE_HOME=$d/cache XDG_CONFIG_HOME=$d/config
      state=$XDG_STATE_HOME/my-theme/mode
      dir=$d
    }
  '';

  # S19/S20 proxy, R8: one driver, the case from $TK_CASE. It runs after
  # start-up (scheduled, so OptionSet fires), performs the case's action,
  # and writes the observed state as JSON to $TK_OUT. The builtin OSC 11
  # handler is never registered headless (no tty UI): setting `background`
  # from Lua stands in for the terminal reply.
  themeDriver = pkgs.writeText "nvf-theme-terminal.lua" ''
    local case, out = os.getenv('TK_CASE'), os.getenv('TK_OUT')
    local cs = 0
    vim.api.nvim_create_autocmd('ColorScheme', { callback = function() cs = cs + 1 end })
    local function normal() return vim.inspect(vim.api.nvim_get_hl(0, { name = 'Normal' })) end
    local r = {}
    local actions = {
      fallback = function() end,
      ['reply-first'] = function() end,
      light = function() vim.o.background = 'light' end,
      dark = function()
        local before, n = normal(), cs
        vim.o.background = 'dark'
        r.normal_changed = normal() ~= before
        -- Neovim's own reload on a 'background' change is one event; the
        -- kit's OptionSet reapply is the second.
        r.colorscheme_events = cs - n
      end,
      ['state-wins'] = function()
        vim.o.background = 'light'
        vim.api.nvim_exec_autocmds('TermResponse',
          { data = { sequence = '\27]11;rgb:ffff/ffff/ffff\27\\' } })
        vim.wait(50)
      end,
    }
    local ok, err = pcall(actions[case])
    r.ok, r.err = ok, ok and "" or tostring(err)
    r.background = vim.o.background
    r.colors_name = vim.g.colors_name or ""
    r.errmsg = vim.v.errmsg
    vim.fn.writefile({ vim.json.encode(r) }, out)
    vim.cmd('qa!')
  '';

  # S28: `yy` then `p` on a line `abc`, three rounds, each timed on its
  # own (start-up excluded). Writes the observations as JSON to $TK_OUT.
  pasteDriver = pkgs.writeText "clipboard-osc52-paste.lua" ''
    local r = { rounds = {} }
    -- osc52.paste announces its wait with nvim_echo(…, history = false),
    -- which never reaches :messages; record it at the call instead.
    r.waiting = false
    local echo = vim.api.nvim_echo
    vim.api.nvim_echo = function(chunks, ...)
      for _, c in ipairs(chunks) do
        if tostring(c[1]):find("Waiting for OSC 52", 1, true) then r.waiting = true end
      end
      return echo(chunks, ...)
    end
    r.provider = vim.fn['provider#clipboard#Executable']()
    for _ = 1, 3 do
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'abc' })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local t0 = vim.uv.hrtime()
      vim.cmd('normal! yy')
      vim.cmd('normal! p')
      local ms = (vim.uv.hrtime() - t0) / 1e6
      table.insert(r.rounds, { ms = ms, lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) })
    end
    r.errmsg = vim.v.errmsg
    vim.fn.writefile({ vim.json.encode(r) }, os.getenv('TK_OUT'))
    vim.cmd('qa!')
  '';
in {
  # S19/S20 proxy, R8, Snippet 8 (+ `reply-first`):
  #   fallback     no state, no reply           → light, enfocado
  #   light        no state, reply light        → light, enfocado
  #   dark         no state, reply dark         → dark, enfocado reapplied
  #                                               (Normal changed; 2 ColorScheme events)
  #   state-wins   state dark, late reply light → dark
  #   reply-first  no state, reply before the config (`--cmd`) → dark
  #   errors       every case: exit 0, v:errmsg == "", no Lua error
  nvf-theme-terminal = pkgs.runCommand "nvf-theme-terminal" {nativeBuildInputs = [pkgs.jq pkgs.coreutils];} ''
    ${prelude}
    run() { # $1: case; rest: extra nvim arguments before the driver
      local c=$1; shift
      fresh "$c"
      rc=0
      TK_CASE=$c TK_OUT=$dir/result.json timeout 60 ${nvim} --headless "$@" \
        -c "lua vim.schedule(function() dofile('${themeDriver}') end)" \
        </dev/null >"$dir/stdout" 2>"$dir/stderr" || rc=$?
      if [ "$rc" -ne 0 ] || [ ! -s "$dir/result.json" ]; then
        bad "$c" "nvim exit $rc, result: $(cat "$dir/result.json" 2>/dev/null), stderr: $(cat "$dir/stderr")"
        return 1
      fi
    }
    expect() { # $1: case; $2: jq condition over the result
      jq -e "$2" "$TMPDIR/$1/result.json" >/dev/null \
        || bad "$1" "want $2, got $(cat "$TMPDIR/$1/result.json")"
    }
    errors='.ok and .errmsg == "" and .err == ""'

    run fallback && {
      expect fallback '.background == "light" and .colors_name == "enfocado"'
      expect fallback "$errors"
    }
    run light && {
      expect light '.background == "light" and .colors_name == "enfocado"'
      expect light "$errors"
    }
    run dark && {
      expect dark '.background == "dark" and .colors_name == "enfocado" and .normal_changed'
      expect dark '.colorscheme_events >= 2'
      expect dark "$errors"
    }
    fresh state-wins; printf 'dark\n' >"$state" # `run` keeps it
    run state-wins && {
      expect state-wins '.background == "dark" and .colors_name == "enfocado"'
      expect state-wins "$errors"
    }
    run reply-first --cmd "lua vim.o.background = 'dark'" && {
      expect reply-first '.background == "dark" and .colors_name == "enfocado"'
      expect reply-first "$errors"
    }

    [ "$fail" -eq 0 ] || exit 1
    touch $out
  '';

  # S28: in Ct (`clipboard = "osc52"`) a paste after a yank is local and
  # fast: the provider is the kit's, every round pastes `abc` below `abc`,
  # the fastest of three `yy`+`p` rounds takes < 100 ms (the minimum, so a
  # load spike in the build does not flake it), and Neovim never waits for
  # an OSC 52 reply.
  clipboard-osc52-paste = pkgs.runCommand "clipboard-osc52-paste" {nativeBuildInputs = [pkgs.jq pkgs.coreutils];} ''
    ${prelude}
    fresh paste
    rc=0
    TK_OUT=$dir/result.json timeout 120 ${nvim} --headless \
      -c "lua vim.schedule(function() dofile('${pasteDriver}') end)" \
      </dev/null >"$dir/stdout" 2>"$dir/stderr" || rc=$?
    r=$dir/result.json
    if [ "$rc" -ne 0 ] || [ ! -s "$r" ]; then
      echo "clipboard-osc52-paste: nvim exit $rc, stderr: $(cat "$dir/stderr")" >&2
      exit 1
    fi
    times=$(jq -c '[.rounds[].ms]' "$r")
    jq -e '.provider == "terminal-kit-osc52"' "$r" >/dev/null \
      || bad clipboard-osc52-paste "provider $(jq -c .provider "$r"), want terminal-kit-osc52"
    jq -e '.rounds | length == 3 and all(.lines == ["abc", "abc"])' "$r" >/dev/null \
      || bad clipboard-osc52-paste "buffer after yy+p: $(jq -c '[.rounds[].lines]' "$r"), want [\"abc\",\"abc\"] each round"
    jq -e '[.rounds[].ms] | min < 100' "$r" >/dev/null \
      || bad clipboard-osc52-paste "fastest yy+p round >= 100 ms; rounds (ms): $times"
    jq -e '.waiting | not' "$r" >/dev/null \
      || bad clipboard-osc52-paste "'Waiting for OSC 52 response' was shown"
    jq -e '.errmsg == ""' "$r" >/dev/null \
      || bad clipboard-osc52-paste "v:errmsg = $(jq -c .errmsg "$r")"
    [ "$fail" -eq 0 ] || exit 1
    echo "clipboard-osc52-paste: rounds (ms): $times"
    touch $out
  '';

  # S21: a running instance follows `nix-terminal-mode dark` within 1 s.
  # The real command (from Ct's packages) signals with its own `pkill`.
  mode-signal = let
    cmd = lib.findFirst (p: lib.getName p == "nix-terminal-mode") null Ct.home.packages;
  in
    if cmd == null
    then
      pkgs.runCommand "mode-signal" {} ''
        echo "mode-signal: nix-terminal-mode is not in Ct's home.packages" >&2
        exit 1
      ''
    else
      pkgs.runCommand "mode-signal" {nativeBuildInputs = [pkgs.coreutils pkgs.procps];} ''
        ${prelude}
        fresh signal
        sock=$dir/s
        timeout 60 ${nvim} --headless --listen "$sock" </dev/null >"$dir/stdout" 2>"$dir/stderr" &
        server=$!
        for _ in $(seq 200); do [ -S "$sock" ] && break; sleep 0.05; done
        remote_bg() { ${nvim} --server "$sock" --remote-expr '&background' 2>/dev/null; }
        before=$(remote_bg)
        [ "$before" = light ] || bad mode-signal "background before: '$before', want light (no state file)"

        ${cmd}/bin/nix-terminal-mode dark || bad mode-signal "nix-terminal-mode dark: exit $?"
        [ "$(cat "$state" 2>/dev/null)" = dark ] || bad mode-signal "state file does not contain dark"

        # poll every 50 ms, for at most 1 s of wall-clock time
        deadline=$(($(date +%s%N) + 1000000000))
        now=$(remote_bg)
        while [ "$now" != dark ] && [ "$(date +%s%N)" -lt "$deadline" ]; do
          sleep 0.05
          now=$(remote_bg)
        done
        [ "$now" = dark ] || bad mode-signal "background still $now after 1 s (stderr: $(cat "$dir/stderr"))"

        kill "$server" 2>/dev/null || true
        wait "$server" 2>/dev/null || true
        [ "$fail" -eq 0 ] || exit 1
        touch $out
      '';
}
