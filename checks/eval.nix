# Eval-level and source-level checks over the kit.
{
  pkgs,
  self,
  tk,
}: let
  inherit (pkgs) lib;
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
}
