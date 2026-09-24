# S26, R10, P7: each alacritty theme package parses as TOML, references no
# store path, and renders exactly the palette of `lib.style` (expected value
# derived from `mkAlacrittyThemeAttrs`, not restated).
{
  pkgs,
  lib,
  style,
  packages,
}: let
  variants = ["light" "dark"];
  expected = v:
    pkgs.writeText "alacritty-theme-enfocado-${v}.json"
    (builtins.toJSON (style.mkAlacrittyThemeAttrs style.palettes.enfocado.${v}));
  checkOne = v: let
    pkg = packages."alacritty-theme-enfocado-${v}";
  in ''
    toml=${pkg}/enfocado-${v}.toml
    if grep -q /nix/store "$toml"; then
      echo "alacritty-theme ${v}: store path in $toml" >&2; fail=1
    fi
    toml2json "$toml" | jq -S . >got-${v}.json
    jq -S . ${expected v} >want-${v}.json
    if ! diff -u want-${v}.json got-${v}.json >&2; then
      echo "alacritty-theme ${v}: colours differ from lib.style (diff above)" >&2; fail=1
    fi
  '';
in
  pkgs.runCommand "alacritty-theme" {nativeBuildInputs = [pkgs.remarshal pkgs.jq pkgs.diffutils pkgs.gnugrep];} ''
    fail=0
    ${lib.concatMapStrings checkOne variants}
    [ "$fail" = 0 ] || exit 1
    touch $out
  ''
