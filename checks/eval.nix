# Eval-level and source-level checks over the kit.
{
  pkgs,
  self,
  tk,
}: let
  inherit (tk) mkCheck ownedHome templateHome Co Ct;

  # --- misc (T6.2, T8.1): fixture -------------------------------------
  # A minimal configuration with the `file` mode source and agent skills
  # left at their default (off). Local on purpose: the nvf branch adds its own `Cf` to lib.nix;
  # the two are deduplicated after the merge.
  fileHomeMisc = tk.mkHome [
    {
      home = {
        username = "tester";
        homeDirectory = "/home/tester";
        stateVersion = "26.05";
      };
      programs.terminalKit = {
        enable = true;
        theme.modeSource = "file";
      };
    }
  ];
  CfMisc = fileHomeMisc.config;
  hasPackage = c: name: lib.any (p: lib.getName p == name) c.home.packages;
  inherit (pkgs) lib;

  # T8.1: the skill directories every skill is linked into (restated, so a
  # new discovery path is a deliberate edit here too).
  skillDirs = [".agents/skills" ".claude/skills"];
  filesByTarget = c:
    lib.listToAttrs (map (f: {
      name = f.target;
      value = f;
    }) (lib.filter (f: f.enable) (lib.attrValues c.home.file)));
  skillLinks = c: lib.filter (t: lib.any (d: lib.hasPrefix "${d}/" t) skillDirs) (tk.targets c);
  sortStrings = lib.sort (a: b: a < b);
  # Problems with the skill links of configuration `c` (label `l`).
  skillLinkProblems = l: c: let
    names = lib.attrNames c.programs.terminalKit.aiSkills.skills;
    files = filesByTarget c;
    expected = lib.concatMap (d: map (n: "${d}/${n}") names) skillDirs;
    missing = lib.filter (t: !(files ? ${t})) expected;
    extra = lib.subtractLists expected (skillLinks c);
    # P3: nothing under ~/.claude but ~/.claude/skills/<name> links.
    claudeOther = lib.filter (t: lib.hasPrefix ".claude" t && !(lib.hasPrefix ".claude/skills/" t)) (tk.targets c);
    # Neither upstream repository root is a skill directory: a linked root
    # has no SKILL.md at depth 1 (ported from ai-skills-source-nested).
    suffixOf = n:
      if n == "xp-clean-code"
      then "/plugins/xp-clean-code/skills/xp-clean-code"
      else "/skills/${n}";
    notNested =
      lib.filter (
        n: let
          f = files.".agents/skills/${n}" or null;
        in
          f != null && !(lib.hasSuffix (suffixOf n) "${f.source}")
      )
      names;
  in
    lib.optional (names == []) "${l}: no skills configured"
    ++ map (t: "${l}: missing link ${t}") missing
    ++ map (t: "${l}: unexpected link ${t}") extra
    ++ map (t: "${l}: ${t} is under .claude but not a skill link (P3)") claudeOther
    ++ map (n: "${l}: source of ${n} is not the nested upstream skill dir") notNested;

  # T8.1: upstream superpowers skills reviewed and deliberately not linked.
  # Adding a name here is the review record for that exclusion.
  superpowersOptOut = [
    # A meta-skill for debugging the superpowers framework itself.
    "diagnosing-superpowers"
  ];
  # --- end misc fixture ------------------------------------------------
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

  # --- misc (T6.2, T8.1) ---------------------------------------------

  # R9: the mode override command exists only with the `terminal` mode
  # source; with `file`, darkman and my-style-switch own the state file.
  mode-command-installed =
    mkCheck "mode-command-installed"
    (hasPackage Ct "nix-terminal-mode"
      && hasPackage Co "nix-terminal-mode"
      && !(hasPackage CfMisc "nix-terminal-mode"))
    "mode-command-installed: nix-terminal-mode must be in Ct and Co (terminal) and absent from CfMisc (file); got Ct=${lib.boolToString (hasPackage Ct "nix-terminal-mode")} Co=${lib.boolToString (hasPackage Co "nix-terminal-mode")} CfMisc=${lib.boolToString (hasPackage CfMisc "nix-terminal-mode")}";

  # S16, P3, D13: every configured skill is linked into both skill
  # directories and nothing else is; nothing else lands under ~/.claude;
  # sources are the nested upstream skill dirs; with aiSkills off (the
  # default) there is no link at all.
  ai-skills-links = let
    problems =
      skillLinkProblems "Ct" Ct
      ++ skillLinkProblems "Co" Co
      ++ map (t: "CfMisc (aiSkills off): unexpected link ${t}") (skillLinks CfMisc)
      ++ map (t: "CfMisc (aiSkills off): unexpected ${t}")
      (lib.filter (lib.hasPrefix ".claude") (tk.targets CfMisc));
  in
    mkCheck "ai-skills-links" (problems == [])
    ("ai-skills-links:\n" + lib.concatStringsSep "\n" problems);

  # Every configured skill exists in its upstream input, and no upstream
  # superpowers skill is left unreviewed (ported from the consuming flake's
  # ai-skills-upstream-inventory). The linked set is read from the
  # configuration; the upstream set from the pinned input:
  #   (a) configured \ upstream              = {}
  #   (b) upstream \ (configured u optOut)   = {}
  ai-skills-inventory = let
    skills = Ct.programs.terminalKit.aiSkills.skills;
    spRoot = "${self.inputs.superpowers}/skills";
    upstream =
      sortStrings (lib.attrNames
        (lib.filterAttrs (_: t: t == "directory") (builtins.readDir spRoot)));
    configuredSp = lib.filter (n: "${skills.${n}}" == "${spRoot}/${n}") (lib.attrNames skills);
    absent = lib.filter (n: !(builtins.pathExists "${skills.${n}}/SKILL.md")) (lib.attrNames skills);
    unreviewed = lib.subtractLists (configuredSp ++ superpowersOptOut) upstream;
    problems =
      lib.optional (skills == {}) "no skills configured"
      ++ map (n: "configured but absent upstream: ${n}") absent
      ++ map (n: "unreviewed upstream superpowers skill: ${n} (link it in ai-skills.nix or add it to superpowersOptOut in checks/eval.nix)") unreviewed;
  in
    mkCheck "ai-skills-inventory" (problems == [])
    ("ai-skills-inventory:\n" + lib.concatStringsSep "\n" problems);

  # --- end misc --------------------------------------------------------
}
