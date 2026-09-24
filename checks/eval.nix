# Eval-level and source-level checks over the kit.
{
  pkgs,
  self,
  tk,
}: let
  inherit (tk) mkCheck ownedHome templateHome Co Ct;
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

  # --- port --- (group 4: the content port, `owned` mode)

  # D4, P20. The expected sets are Appendix A's names (A.12), not a list the
  # module exports: the criterion stays independent of the implementation.
  # Cₒ has every package of both sets and devenv's program; Cₜ (dev off) has
  # no package of the dev set, except one that an enabled program of the kit
  # installs itself (direnv is in the dev set and is also `tools.direnv`).
  packages-sets = let
    lib = pkgs.lib;
    general = ["htop" "iotop" "lsof" "wget" "ripgrep" "fd" "tree" "unzip" "zip" "file" "jq"];
    dev = ["clang" "gnumake" "cmakeCurses" "nodejs" "docker-compose" "direnv" "devenv"];
    outs = c: map (p: p.outPath) c.home.packages;
    # The Home Manager programs the kit enables (a literal list: iterating
    # `c.programs` would force removed-option shims, which throw).
    kitPrograms = ["bat" "btop" "lazygit" "fzf" "starship" "zoxide" "direnv" "nix-index" "devenv" "yazi" "git" "zsh" "bash"];
    programPkgs = c:
      map (p: c.programs.${p}.package.outPath)
      (lib.filter (p: c.programs.${p}.enable) kitPrograms);
    missingCo = lib.filter (n: !(lib.elem pkgs.${n}.outPath (outs Co))) (general ++ dev);
    missingCt = lib.filter (n: !(lib.elem pkgs.${n}.outPath (outs Ct))) general;
    offendersCt =
      lib.filter (n: lib.elem pkgs.${n}.outPath (outs Ct) && !(lib.elem pkgs.${n}.outPath (programPkgs Ct))) dev;
  in
    mkCheck "packages-sets"
    (missingCo == [] && missingCt == [] && offendersCt == [] && Co.programs.devenv.enable && !Ct.programs.devenv.enable)
    "packages-sets: missing in Co: ${toString missingCo}; missing in Ct: ${toString missingCt}; dev packages in Ct (P20): ${toString offendersCt}; devenv Co=${lib.boolToString Co.programs.devenv.enable} Ct=${lib.boolToString Ct.programs.devenv.enable}";

  # T4.2. Every tool is on in Cₒ and installs its package. With the tools
  # switched off (and with the kit disabled) none is on — nix-index
  # included, which nix-index-database's module turns on by default.
  tools = let
    lib = pkgs.lib;
    # κ.tools name -> Home Manager program
    hm = {
      bat = "bat";
      btop = "btop";
      lazygit = "lazygit";
      fzf = "fzf";
      starship = "starship";
      zoxide = "zoxide";
      direnv = "direnv";
      nixIndex = "nix-index";
    };
    user.home = {
      username = "tester";
      homeDirectory = "/home/tester";
      stateVersion = "26.05";
    };
    toolsOff =
      (tk.mkHome [
        user
        {
          programs.terminalKit = {
            enable = true;
            tools = lib.mapAttrs (_: _: {enable = false;}) hm;
          };
        }
      ]).config;
    kitOff = (tk.mkHome [user]).config;
    outs = map (p: p.outPath) Co.home.packages;
    notOn = lib.filter (t: !Co.programs.${t}.enable) (lib.attrValues hm);
    noPkg = lib.filter (t: Co.programs.${t}.enable && !(lib.elem Co.programs.${t}.package.outPath outs)) (lib.attrValues hm);
    stillOn = c: lib.filter (t: c.programs.${t}.enable) (lib.attrValues hm);
  in
    mkCheck "tools"
    (notOn == [] && noPkg == [] && stillOn toolsOff == [] && stillOn kitOff == [] && Co.programs.direnv.nix-direnv.enable)
    "tools: off in Co: ${toString notOn}; package missing in Co: ${toString noPkg}; on with tools off: ${toString (stillOn toolsOff)}; on with the kit disabled: ${toString (stillOn kitOff)}; nix-direnv=${lib.boolToString Co.programs.direnv.nix-direnv.enable}";

  # T4.3, R8. Cₒ's yazi flavor files are lib.style's enfocado flavors
  # (expected value derived from `mkYaziFlavor`, compared as parsed TOML),
  # the theme selects them per mode, and κ.yazi.flavorOverrides merges
  # into the one mode it names.
  yazi-flavors = let
    lib = pkgs.lib;
    inherit (self.lib) style;
    withOverride =
      (tk.mkHome [
        {
          home = {
            username = "tester";
            homeDirectory = "/home/tester";
            stateVersion = "26.05";
          };
          programs.terminalKit = {
            enable = true;
            yazi.flavorOverrides.light.mgr.cwd.fg = "#123456";
          };
        }
      ]).config;
    y = Co.programs.yazi;
    evalOk =
      y.enable
      && y.shellWrapperName == "yy"
      && y.enableZshIntegration
      && y.theme.flavor
      == {
        dark = "enfocado-dark";
        light = "enfocado-light";
      };
    compare = v: ''
      toml2json ${y.flavors."enfocado-${v}"}/flavor.toml | jq -S . >got-${v}.json
      toml2json ${pkgs.writeText "want-${v}.toml" (style.mkYaziFlavor style.palettes.enfocado.${v})} | jq -S . >want-${v}.json
      if ! diff -u want-${v}.json got-${v}.json >&2; then
        echo "yazi-flavors: enfocado-${v} differs from mkYaziFlavor palettes.${v} (diff above)" >&2; fail=1
      fi
    '';
    ov = withOverride.programs.yazi.flavors;
  in
    pkgs.runCommand "yazi-flavors" {nativeBuildInputs = [pkgs.remarshal pkgs.jq pkgs.diffutils];} ''
      fail=0
      ${lib.optionalString (!evalOk) ''
        echo "yazi-flavors: Co's programs.yazi (enable, yy wrapper, zsh integration, theme.flavor) is not the kit's" >&2; fail=1
      ''}
      ${lib.concatMapStrings compare ["light" "dark"]}
      [ "$(toml2json ${ov.enfocado-light}/flavor.toml | jq -r .mgr.cwd.fg)" = "#123456" ] \
        || { echo "yazi-flavors: flavorOverrides.light not merged into enfocado-light" >&2; fail=1; }
      [ "$(toml2json ${ov.enfocado-dark}/flavor.toml | jq -r .mgr.cwd.fg)" != "#123456" ] \
        || { echo "yazi-flavors: flavorOverrides.light leaked into enfocado-dark" >&2; fail=1; }
      [ "$fail" = 0 ] || exit 1
      touch $out
    '';

  # T4.4a, D22, P19. Identity-dependent git content is written only with
  # the identity it needs: user.* per value, signing with signingKey,
  # cycle/mylatest with name, resign*/format.signOff with name and email.
  # Cₒ has all of it; Cₜ (no identity) none; a name-only config the
  # name-only part.
  git-identity = let
    lib = pkgs.lib;
    nameOnly =
      (tk.mkHome [
        {
          home = {
            username = "tester";
            homeDirectory = "/home/tester";
            stateVersion = "26.05";
          };
          programs.terminalKit = {
            enable = true;
            git.name = "tester";
          };
        }
      ]).config;
    s = c: c.programs.git.settings;
    aliasNames = c: lib.attrNames ((s c).alias or {});
    nameAliases = ["cycle" "mylatest"];
    fullAliases = ["resign" "resign-om" "resign-head"];
    has = c: names: lib.all (n: lib.elem n (aliasNames c)) names;
    hasNone = c: names: !(lib.any (n: lib.elem n (aliasNames c)) names);
    signOff = c: (s c).format.signOff or null;
    gpg = c: [((s c).commit.gpgsign or null) ((s c).tag.gpgsign or null)];
    problems =
      lib.optional (!Co.programs.git.enable) "git off in Co"
      ++ lib.optional (!(has Co ["st" "lgg" "review"])) "public aliases missing in Co"
      ++ lib.optional ((s Co).user or null
        != {
          name = "tester";
          email = "tester@example.invalid";
          signingkey = "DEADBEEF";
        }) "Co user.* = ${builtins.toJSON ((s Co).user or null)}"
      ++ lib.optional (gpg Co != [true true]) "Co commit/tag.gpgsign = ${builtins.toJSON (gpg Co)}"
      ++ lib.optional (signOff Co != true) "Co format.signOff unset"
      ++ lib.optional (!(has Co (nameAliases ++ fullAliases))) "Co lacks ${toString (nameAliases ++ fullAliases)}"
      ++ lib.optional ((s Ct) ? user) "Ct user.* = ${builtins.toJSON (s Ct).user}"
      ++ lib.optional (gpg Ct != [null null]) "Ct commit/tag.gpgsign = ${builtins.toJSON (gpg Ct)}"
      ++ lib.optional (signOff Ct != null) "Ct format.signOff set"
      ++ lib.optional (!(hasNone Ct (nameAliases ++ fullAliases))) "Ct has an identity alias"
      ++ lib.optional ((s nameOnly).user or null != {name = "tester";}) "name-only user.* = ${builtins.toJSON ((s nameOnly).user or null)}"
      ++ lib.optional (!(has nameOnly nameAliases) || !(hasNone nameOnly fullAliases)) "name-only: wrong identity aliases"
      ++ lib.optional (signOff nameOnly != null) "name-only format.signOff set";
  in
    mkCheck "git-identity" (problems == []) "git-identity: ${lib.concatStringsSep "; " problems}";

  # T4.4b, R16 `par`. `clus` clones from κ.git.githubUser's fork: present
  # in Cₒ (githubUser = "tester", body otherwise the original's), absent
  # in Cₜ (githubUser = null).
  git-clus = let
    lib = pkgs.lib;
    want = "!f() { IN=(\${1//// }); git clone git@github.com:tester/\${IN[1]} && cd \${IN[1]} && git remote add upstream git@github.com:$1 && git remote -v ; }; f";
    got = c: c.programs.git.settings.alias.clus or null;
  in
    mkCheck "git-clus" (got Co == want && got Ct == null)
    "git-clus: Co clus = ${builtins.toJSON (got Co)} (want ${builtins.toJSON want}); Ct clus = ${builtins.toJSON (got Ct)} (want null)";

  # T4.4b, P18 for git. κ.git.extraAliases merge into the aliases,
  # κ.git.includes reach programs.git.includes, and κ.git.tigExtraConfig
  # is appended to the kit's tig/config (Cₒ, without it, gets the file
  # unchanged).
  git-hooks = let
    lib = pkgs.lib;
    tigExtra = "bind generic Z !true\n";
    include = {
      condition = "gitdir:~/work/";
      path = "~/work/.gitconfig";
    };
    hooked =
      (tk.mkHome [
        {
          home = {
            username = "tester";
            homeDirectory = "/home/tester";
            stateVersion = "26.05";
          };
          programs.terminalKit = {
            enable = true;
            git.includes = [include];
            git.tigExtraConfig = tigExtra;
          };
        }
      ]).config;
    base = builtins.readFile "${self}/modules/terminal-kit/git/tig/config";
    tig = c: c.xdg.configFile."tig/config".text;
    problems =
      lib.optional ((Co.programs.git.settings.alias.tk-probe or null) != "status") "Co alias tk-probe missing"
      ++ lib.optional (!(lib.any (i: i.condition == include.condition && i.path == include.path) hooked.programs.git.includes)) "includes not passed to programs.git.includes"
      ++ lib.optional (tig Co != base) "Co tig/config is not the kit's file"
      ++ lib.optional (tig hooked != base + tigExtra) "tigExtraConfig not appended to tig/config";
  in
    mkCheck "git-hooks" (problems == []) "git-hooks: ${lib.concatStringsSep "; " problems}";

  # T4.5. The public session variables of A.2 are set (with their values)
  # in Cₒ and Cₜ; none of the desktop ones is.
  env = let
    lib = pkgs.lib;
    public = {
      EDITOR = "nvim";
      SUDO_EDITOR = "nvim";
      VISUAL = "nvim";
      SBT_OPTS = "-Xms1G -Xmx4G -Xss16M";
      AUTOSSH_GATETIME = "0";
    };
    desktop = ["BROWSER" "_JAVA_AWT_WM_NONREPARENTING" "AWT_TOOLKIT" "QT_QPA_PLATFORMTHEME" "XCURSOR_SIZE" "NIXOS_OZONE_WL"];
    wrong = c: lib.filter (n: (c.home.sessionVariables.${n} or null) != public.${n}) (lib.attrNames public);
    desk = c: lib.filter (n: c.home.sessionVariables ? ${n}) desktop;
  in
    mkCheck "env" (wrong Co == [] && wrong Ct == [] && desk Co == [] && desk Ct == [])
    "env: missing or different in Co: ${toString (wrong Co)}; in Ct: ${toString (wrong Ct)}; desktop variables in Co: ${toString (desk Co)}; in Ct: ${toString (desk Ct)}";

  # T4.6a, P18, F2, R15. zsh is on with the kit's aliases (a sample of
  # A.1's public rows, the A.15 Q1/Q2 ones included) and κ.zsh.extraAliases
  # merged in; history goes to κ.zsh.historyPath; dotDir is explicit;
  # zsh-system-clipboard is loaded only with clipboard = "system" (Cₒ),
  # not with "osc52" (Cₜ).
  zsh-hooks = let
    lib = pkgs.lib;
    z = c: c.programs.zsh;
    # T4.6b: initContent. A sample of A.1's public functions and settings;
    # HISTFILE is set once (Home Manager's history.path line, not a
    # second literal); κ.zsh.extraInit comes after the kit's content.
    probeInit = "tk_probe_init() { :; }";
    withInit =
      (tk.mkHome [
        {
          home = {
            username = "tester";
            homeDirectory = "/home/tester";
            stateVersion = "26.05";
          };
          programs.terminalKit = {
            enable = true;
            zsh.extraInit = probeInit;
          };
        }
      ]).config;
    lastPublic = "function ollama_update() {";
    initLines = c: map lib.trim (lib.splitString "\n" (z c).initContent);
    initSample = ["function precmd {" "export KEYTIMEOUT=1" "cdg() {" "fif() {" "drclean?() {" "search_replace() {" lastPublic];
    initMissing = c: lib.filter (l: !(lib.elem l (initLines c))) initSample;
    histfile = c: lib.filter (lib.hasPrefix "HISTFILE=") (initLines c);
    indexOf = l: c: lib.lists.findFirstIndex (x: x == l) null (initLines c);
    initAfter = let
      i = indexOf probeInit withInit;
      j = indexOf lastPublic withInit;
    in
      i != null && j != null && i > j;
    sample = ["rm" "ls" "cdp" "t" "nd" "ssh" "rcp" "v" "g" "dr" "drps" "has_dns" "won" "serve" "nload"];
    missing = c: lib.filter (a: !((z c).shellAliases ? ${a})) sample;
    plugins = c: map (p: p.name) (z c).plugins;
    problems =
      lib.optional (!(z Co).enable || !(z Ct).enable) "zsh off"
      ++ lib.optional (missing Co != []) "Co lacks aliases ${toString (missing Co)}"
      ++ lib.optional (missing Ct != []) "Ct lacks aliases ${toString (missing Ct)}"
      ++ lib.optional (((z Co).shellAliases.tk-probe or null) != "true") "Co: κ.zsh.extraAliases.tk-probe not merged"
      ++ lib.optional ((z Co).shellGlobalAliases.H or null != "| head") "Co: global alias H missing"
      ++ lib.optional ((z Co).history.path != Co.programs.terminalKit.zsh.historyPath) "Co history.path = ${(z Co).history.path}"
      ++ lib.optional ((z Ct).history.path != Ct.programs.terminalKit.zsh.historyPath) "Ct history.path = ${(z Ct).history.path}"
      ++ lib.optional ((z Co).dotDir != "${Co.xdg.configHome}/zsh") "Co dotDir = ${toString (z Co).dotDir}"
      ++ lib.optional (!(lib.elem "zsh-system-clipboard" (plugins Co))) "Co (system clipboard) lacks zsh-system-clipboard"
      ++ lib.optional (lib.elem "zsh-system-clipboard" (plugins Ct)) "Ct (osc52) loads zsh-system-clipboard"
      ++ lib.optional (!(lib.all (p: lib.elem p (plugins Ct)) ["zsh-print-alias" "mill-zsh-completions"])) "Ct lacks a public plugin"
      ++ lib.optional (initMissing Co != []) "Co initContent lacks: ${lib.concatStringsSep " | " (initMissing Co)}"
      ++ lib.optional (lib.length (histfile Co) != 1) "Co HISTFILE lines: ${builtins.toJSON (histfile Co)}"
      ++ lib.optional (!initAfter) "κ.zsh.extraInit is not after the kit's initContent";
  in
    mkCheck "zsh-hooks" (problems == []) "zsh-hooks: ${lib.concatStringsSep "; " problems}";

  # T4.7, F17, R5. Terminal-only output in Cₒ's initContent (cursor-shape
  # and title escapes, the bell, tput) runs only with a terminal on
  # stdout: every such line lies inside an `if [[ -t 1 ]]; then … fi`
  # block, or follows `[[ -t 1 ]] || return` in its function. Line-based
  # scan (splitString, hasInfix), no regex.
  zsh-tty-guard = let
    lib = pkgs.lib;
    patterns = ["echo -ne '\\e[" "echo -ne \"\\e[" "printf '\\e[" "(tput " "\\007" "\\e]0;" "\\033]0;"];
    isOutput = t: lib.any (p: lib.hasInfix p t) patterns;
    isIf = t: lib.hasPrefix "if " t && lib.hasSuffix "then" t;
    step = s: line: let
      t = lib.trim line;
      bad = isOutput t && s.guard == 0 && !s.fn;
    in {
      guard =
        if s.guard > 0
        then
          (
            if isIf t
            then s.guard + 1
            else if t == "fi"
            then s.guard - 1
            else s.guard
          )
        else if t == "if [[ -t 1 ]]; then"
        then 1
        else 0;
      fn =
        if t == "[[ -t 1 ]] || return"
        then true
        else if t == "}"
        then false
        else s.fn;
      bad = s.bad ++ lib.optional bad t;
    };
    result = lib.foldl' step {
      guard = 0;
      fn = false;
      bad = [];
    } (lib.splitString "\n" Co.programs.zsh.initContent);
    # The scan must see the lines it guards: at least the start-up cursor
    # escape and the LESS_TERMCAP tput calls.
    seen = lib.filter isOutput (lib.splitString "\n" Co.programs.zsh.initContent);
  in
    mkCheck "zsh-tty-guard" (result.bad == [] && lib.length seen >= 14)
    "zsh-tty-guard: unguarded terminal output: ${lib.concatStringsSep " | " result.bad} (lines matched: ${toString (lib.length seen)})";

  # T4.8, P18 for bash. bash is on in Cₒ and Cₜ, and κ.bash.extraAliases
  # reach programs.bash.shellAliases.
  bash-aliases = let
    lib = pkgs.lib;
    b = c: c.programs.bash;
  in
    mkCheck "bash-aliases"
    ((b Co).enable && (b Ct).enable && ((b Co).shellAliases.tk-probe or null) == "true")
    "bash-aliases: bash Co=${lib.boolToString (b Co).enable} Ct=${lib.boolToString (b Ct).enable}; Co tk-probe = ${builtins.toJSON ((b Co).shellAliases.tk-probe or null)} (want \"true\")";
  # --- end port ---
}
