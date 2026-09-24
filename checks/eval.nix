# Eval-level and source-level checks over the kit.
{
  pkgs,
  self,
  tk,
}: let
  inherit (tk) mkCheck ownedHome templateHome Co Ct;

  # --- tmpl --- (T9.1, T9.4)
  # The template flake, evaluated offline: its `outputs` function is called
  # with stub inputs built from this flake's own inputs, with this flake as
  # `nix-terminal` (what `follows` resolves to after `nix flake init`).
  templateDir = "${self}/templates/coder";
  templateFlakePresent = builtins.pathExists "${templateDir}/flake.nix";
  templateFlake = import "${templateDir}/flake.nix";
  templateOutputs = templateFlake.outputs {
    self = templateOutputs // {outPath = templateDir;};
    nix-terminal = self;
    inherit (self.inputs) nixpkgs home-manager;
  };
  templateUser = import "${templateDir}/user.nix";
  # Messages of the failed conditions in `cs` (a list of [cond msg]).
  failures = cs: map (c: builtins.elemAt c 1) (builtins.filter (c: !(builtins.head c)) cs);
  # --- end tmpl ---
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
  # --- end port ---

  # --- tmpl --- (T9.1, T9.4)

  # S1 proxy, R17. Cₜ carries R17's settings; the user file has exactly
  # R17's edits; and the template flake builds exactly Cₜ, so every check
  # over Cₜ covers what the flake builds (including system x86_64-linux).
  template-evaluates = let
    kit = Ct.programs.terminalKit;
    hc = templateOutputs.homeConfigurations.${templateUser.name} or null;
    problems = failures [
      [(builtins.attrNames templateUser == ["homeDirectory" "name" "stateVersion"]) "user.nix has fields ${toString (builtins.attrNames templateUser)}; R17 allows exactly homeDirectory name stateVersion"]
      [(Ct.home.username == "coder" && Ct.home.homeDirectory == "/home/coder") "user defaults are ${Ct.home.username} ${Ct.home.homeDirectory}, expected coder /home/coder"]
      [(Ct.home.stateVersion == templateUser.stateVersion) "home.stateVersion is not user.nix's"]
      [Ct.programs.home-manager.enable "programs.home-manager.enable is off"]
      [kit.enable "the kit is disabled"]
      [(kit.shellIntegration == "sourced") "shellIntegration = ${kit.shellIntegration}"]
      [(kit.clipboard == "osc52") "clipboard = ${kit.clipboard}"]
      [(kit.theme.modeSource == "terminal") "theme.modeSource = ${kit.theme.modeSource}"]
      [kit.aiSkills.enable "aiSkills.enable is off"]
      [(!kit.packages.dev.enable) "packages.dev.enable is on"]
      [(kit.git.name == null && kit.git.email == null && kit.git.signingKey == null) "a git identity is set (D22)"]
      [templateFlakePresent "templates/coder/flake.nix does not exist"]
      [(templateFlakePresent && hc != null) "the template flake has no homeConfigurations.${templateUser.name}"]
      [(templateFlakePresent && hc != null && hc.activationPackage.drvPath == Ct.home.activationPackage.drvPath) "the template flake's homeConfigurations.${templateUser.name} is not Ct"]
    ];
  in
    mkCheck "template-evaluates" (problems == []) "template-evaluates: ${pkgs.lib.concatStringsSep "; " problems}";

  # S2 proxy, R17. The template pins the home-manager CLI through
  # nix-terminal's inputs and exposes it as a package, next to the home
  # configuration named after user.nix.
  template-exposes-hm-cli = let
    lib = pkgs.lib;
    ins = templateFlake.inputs or {};
    hmCli = ["packages" "x86_64-linux" "home-manager"];
    problems = failures [
      [templateFlakePresent "templates/coder/flake.nix does not exist"]
      [(templateFlakePresent && (ins.nix-terminal.url or null) == "github:GRBurst/nix-terminal") "inputs.nix-terminal.url is not github:GRBurst/nix-terminal"]
      [(templateFlakePresent && (ins.nixpkgs.follows or null) == "nix-terminal/nixpkgs") "inputs.nixpkgs does not follow nix-terminal/nixpkgs"]
      [(templateFlakePresent && (ins.home-manager.follows or null) == "nix-terminal/home-manager") "inputs.home-manager does not follow nix-terminal/home-manager"]
      [(templateFlakePresent && lib.hasAttrByPath hmCli templateOutputs) "packages.x86_64-linux.home-manager is missing"]
      [(templateFlakePresent && lib.hasAttrByPath hmCli templateOutputs && (lib.getAttrFromPath hmCli templateOutputs).outPath == self.inputs.home-manager.packages.x86_64-linux.home-manager.outPath) "packages.x86_64-linux.home-manager is not the pinned home-manager CLI"]
      [(templateFlakePresent && builtins.attrNames (templateOutputs.homeConfigurations or {}) == [templateUser.name]) "homeConfigurations is not exactly [${templateUser.name}]"]
    ];
  in
    mkCheck "template-exposes-hm-cli" (problems == []) "template-exposes-hm-cli: ${lib.concatStringsSep "; " problems}";

  # R1. The flake exports exactly R1's output groups (what `nix flake show`
  # lists), each with R1's members, and the root has the MIT LICENSE (D20).
  outputs-shape = let
    lib = pkgs.lib;
    o = self.outputs;
    names = s: builtins.attrNames (o.${s} or {});
    groups = ["checks" "formatter" "homeModules" "lib" "packages" "templates"];
    themes = ["alacritty-theme-enfocado-dark" "alacritty-theme-enfocado-light"];
    pkgsOut = o.packages.x86_64-linux or {};
    notMit = lib.filter (n: (pkgsOut.${n}.meta.license.spdxId or null) != "MIT") (lib.intersectLists themes (builtins.attrNames pkgsOut));
    licence = builtins.readFile "${self}/LICENSE";
    problems = failures [
      [(builtins.attrNames o == groups) "output groups are ${toString (builtins.attrNames o)}, expected ${toString groups}"]
      [(names "homeModules" == ["default"]) "homeModules: ${toString (names "homeModules")}, expected default"]
      [(names "lib" == ["style"]) "lib: ${toString (names "lib")}, expected style"]
      [(names "templates" == ["coder"]) "templates: ${toString (names "templates")}, expected coder"]
      [(names "packages" == ["x86_64-linux"] && builtins.attrNames pkgsOut == themes) "packages: ${toString (names "packages")} / ${toString (builtins.attrNames pkgsOut)}, expected x86_64-linux / ${toString themes}"]
      [(notMit == []) "packages without MIT licence metadata: ${toString notMit}"]
      [(names "checks" == ["x86_64-linux"]) "checks systems: ${toString (names "checks")}"]
      [(names "formatter" == ["x86_64-linux"] && (o.formatter.x86_64-linux.outPath or null) == pkgs.alejandra.outPath) "formatter.x86_64-linux is not Alejandra"]
      [(lib.hasPrefix "MIT License\n" licence && lib.hasInfix "Copyright (c) 2026 GRBurst\n" licence) "LICENSE is not the MIT licence of D20"]
    ];
  in
    mkCheck "outputs-shape" (problems == []) "outputs-shape: ${lib.concatStringsSep "; " problems}";

  # R1, §6. Every workflow passes actionlint (with shellcheck for `run:`),
  # and one runs `nix flake check --keep-going` on every push.
  ci-workflow-lint =
    pkgs.runCommand "ci-workflow-lint" {
      nativeBuildInputs = [pkgs.actionlint pkgs.shellcheck pkgs.yq-go pkgs.jq];
    } ''
      cd ${self}
      wf=.github/workflows/check.yml
      if [ ! -f "$wf" ]; then
        echo "ci-workflow-lint: $wf does not exist" >&2
        exit 1
      fi
      actionlint -no-color .github/workflows/*.yml >&2 || {
        echo "ci-workflow-lint: actionlint failed" >&2
        exit 1
      }
      # `on` as a string, a list or a map; push without branch filters.
      push=$(yq -o json '.on' "$wf" | jq 'if type == "string" then [.] elif type == "array" then . else to_entries | map(select(.value == null) | .key) end | index("push") != null')
      if [ "$push" != true ]; then
        echo "ci-workflow-lint: $wf does not run on every push" >&2
        exit 1
      fi
      runs=$(yq '[.jobs[].steps[].run | select(. != null) | select(test("nix flake check --keep-going"))] | length' "$wf")
      if [ "$runs" -lt 1 ]; then
        echo "ci-workflow-lint: no step of $wf runs 'nix flake check --keep-going'" >&2
        exit 1
      fi
      touch $out
    '';
  # --- end tmpl ---
}
