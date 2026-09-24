# Eval-level and source-level checks over the kit.
{
  pkgs,
  self,
  tk,
}: let
  inherit (pkgs) lib;
  inherit (tk) mkCheck ownedHome templateHome Co Ct Cf fileHome;
in {
  # R2, D11, D12, P15: the kit reads neither `osConfig` nor any Stylix
  # option, so it evaluates the same standalone and inside NixOS.
  # `self` is read-only: every write goes to $TMPDIR.
  no-os-config = pkgs.runCommand "no-os-config" {nativeBuildInputs = [pkgs.ripgrep];} ''
    hits=$TMPDIR/hits
    cd ${self}
    dirs=()
    for d in modules lib packages templates; do
      if [ -d "$d" ]; then dirs+=("$d"); fi
    done
    rc=1 # no dirs: nothing to find
    if [ "''${#dirs[@]}" -gt 0 ]; then
      rc=0
      rg --line-number --with-filename --hidden --no-ignore 'osConfig|stylix\.' "''${dirs[@]}" >"$hits" || rc=$?
    fi
    case $rc in
      0) echo "no-os-config: forbidden tokens:" >&2; cat "$hits" >&2; exit 1 ;;
      1) ;;
      *) echo "no-os-config: rg failed ($rc)" >&2; exit 1 ;;
    esac
    touch $out
  '';

  # R2: both test configurations evaluate down to the activation package,
  # with no Stylix module anywhere in the evaluation. The option tree is
  # forced as well: a value is type-checked only when it is read, and a
  # sub-module may not read every option.
  configs-evaluate =
    mkCheck "configs-evaluate"
    (
      builtins.isString Co.home.activationPackage.drvPath
      && builtins.isString Ct.home.activationPackage.drvPath
      && builtins.deepSeq Co.programs.terminalKit true
      && builtins.deepSeq Ct.programs.terminalKit true
      && !(ownedHome.options ? stylix)
      && !(templateHome.options ? stylix)
    )
    "configs-evaluate: a Stylix option is declared in a test configuration";

  # D23, PD12: the kit's 79 keymaps (the private flake's 80 minus the private
  # `<leader>vv`) come first, and `nvf.extraKeymaps` follow them.
  nvf-extra-keymaps = let
    maps = Co.programs.nvf.settings.vim.keymaps;
    extra = Co.programs.terminalKit.nvf.extraKeymaps;
    view = k: {inherit (k) mode key action desc;};
    kitCount = lib.length maps - lib.length extra;
    keys = map (k: k.key) maps;
  in
    mkCheck "nvf-extra-keymaps"
    (
      Co.programs.nvf.enable
      && extra != []
      && kitCount == 79
      && map view (lib.drop kitCount maps) == map view extra
      && !(lib.elem "<leader>vv" keys)
    )
    "nvf-extra-keymaps: want 79 kit keymaps (no <leader>vv), then ${builtins.toJSON (map view extra)}; got keys ${builtins.toJSON keys}";

  # D23, F18: in `file` mode the generated Lua carries the private flake's
  # theme hook verbatim at the head of its `custom-functions` section, and
  # vim-enfocado is built exactly as there. The expected values are copied
  # from the private flake's features/nvf.nix (the consuming flake cannot be
  # read from here). With `theme.enable = false` neither is shipped.
  nvf-file-mode = let
    vim = c: c.programs.nvf.settings.vim;
    linesOf = c: lib.splitString "\n" (vim c).builtLuaConfigRC;
    # every index at which `block` occurs in `lines` (linear in `lines`)
    occurrences = block: lines: let
      n = lib.length block;
      starts = lib.filter (i: lib.elemAt lines i == lib.head block) (lib.range 0 (lib.length lines - n));
    in
      lib.filter (i: lib.sublist i n lines == block) starts;
    hook = lib.splitString "\n" ''
      -- SECTION: custom-functions
      -- Follow the shared darkman mode state without rebuilding Neovim.
      local function apply_enfocado_mode()
        local state_home = vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")
        local mode_file = state_home .. "/my-theme/mode"
        local ok, lines = pcall(vim.fn.readfile, mode_file)
        local mode = ok and lines[1] or "light"

        if mode ~= "dark" then
          mode = "light"
        end

        vim.o.background = mode
        vim.g.enfocado_style = "nature"
        pcall(vim.cmd.colorscheme, "enfocado")
      end

      apply_enfocado_mode()
      vim.api.nvim_create_autocmd("Signal", {
        pattern = "SIGUSR1",
        callback = apply_enfocado_mode,
      })

      -- Smart Home: toggle between col 0 and first non-blank'';
    pin = {
      pname = "vim-enfocado";
      version = "unstable-2026-04-29";
      rev = "2a8fffdff1a20473f0fbacef10f2fb356e039b31";
      outputHash = "1ircbl87rxn2l7frywg8xr88y63vqkjp0zfk5j5fc5cryvzrzvmk";
    };
    pluginOf = c: let
      p = (vim c).extraPlugins.vim-enfocado.package or null;
    in
      if p == null
      then null
      else {
        inherit (p) pname version;
        inherit (p.src) rev outputHash;
      };
    neon =
      (fileHome.extendModules {
        modules = [{programs.terminalKit.theme.nvf.enfocadoStyle = "neon";}];
      }).config;
    off =
      (fileHome.extendModules {
        modules = [{programs.terminalKit.theme.enable = false;}];
      }).config;
    L = linesOf Cf;
    offText = (vim off).builtLuaConfigRC;
  in
    mkCheck "nvf-file-mode"
    (
      lib.length (occurrences hook L)
      == 1
      && pluginOf Cf == pin
      && lib.filter (l: lib.hasInfix "enfocado_style" l) (linesOf neon) == ["  vim.g.enfocado_style = \"neon\""]
      && pluginOf off == null
      && !(lib.hasInfix "apply_enfocado_mode" offText)
      && !(lib.hasInfix "/my-theme/mode" offText)
    )
    (lib.concatStringsSep "\n" [
      "nvf-file-mode:"
      "  hook occurrences: ${toString (lib.length (occurrences hook L))} (want 1)"
      "  hook lines missing: ${builtins.toJSON (lib.filter (l: !(lib.elem l L)) hook)}"
      "  plugin: ${builtins.toJSON (pluginOf Cf)} (want ${builtins.toJSON pin})"
      "  enfocadoStyle = \"neon\": ${builtins.toJSON (lib.filter (l: lib.hasInfix "enfocado_style" l) (linesOf neon))}"
      "  theme.enable = false: plugin ${builtins.toJSON (pluginOf off)}, hook ${lib.boolToString (lib.hasInfix "apply_enfocado_mode" offText)}, state file ${lib.boolToString (lib.hasInfix "/my-theme/mode" offText)}"
    ]);
}
