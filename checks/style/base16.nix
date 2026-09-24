{
  pkgs,
  lib,
  ...
}: let
  style = import ../../lib/style {inherit lib;};
  light = (import ../../lib/style/enfocado.nix).light;
  dark = (import ../../lib/style/enfocado.nix).dark;
  bL = style.toBase16 light;
  bD = style.toBase16 dark;
  expect = label: e: a:
    if e == a
    then null
    else throw "base16 mismatch ${label}: expected ${e}, got ${a}";
in
  pkgs.runCommand "check-toBase16" {} ''
    ${builtins.toString (lib.filter (x: x != null) [
      (expect "L.base00" "ffffff" bL.base00)
      (expect "L.base01" "ebebeb" bL.base01)
      (expect "L.base02" "cdcdcd" bL.base02)
      (expect "L.base03" "878787" bL.base03)
      (expect "L.base05" "474747" bL.base05)
      (expect "L.base07" "282828" bL.base07)
      (expect "L.base0F" "7f51d6" bL.base0F)
      (expect "D.base00" "181818" bD.base00)
      (expect "D.base03" "3b3b3b" bD.base03)
      (expect "D.base05" "b9b9b9" bD.base05)
      (expect "D.base07" "dedede" bD.base07)
      (expect "D.base0F" "a580e2" bD.base0F)
    ])}
    touch $out
  ''
