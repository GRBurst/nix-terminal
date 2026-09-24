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

  # --- end misc --------------------------------------------------------
}
