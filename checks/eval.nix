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
  # --- end port ---
}
