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
  # --- end port ---
}
