{
  pkgs,
  lib,
  ...
}: let
  palettes = import ../../lib/style/enfocado.nix;
  expect = name: expected: actual:
    if expected == actual
    then null
    else throw "palette mismatch ${name}: expected ${expected}, got ${actual}";
in
  pkgs.runCommand "check-enfocado-palette" {} ''
    ${builtins.toString (lib.filter (x: x != null) [
      (expect "light.normal.black" "#ebebeb" palettes.light.normal.black)
      (expect "light.normal.white" "#878787" palettes.light.normal.white)
      (expect "light.bright.black" "#cdcdcd" palettes.light.bright.black)
      (expect "light.bright.white" "#282828" palettes.light.bright.white)
      (expect "light.bright.red" "#bf0000" palettes.light.bright.red)
      (expect "light.normal.orange" "#d04a00" palettes.light.normal.orange)
      (expect "light.normal.violet" "#7f51d6" palettes.light.normal.violet)
      (expect "dark.normal.black" "#252525" palettes.dark.normal.black)
      (expect "dark.normal.white" "#777777" palettes.dark.normal.white)
      (expect "dark.bright.black" "#3b3b3b" palettes.dark.bright.black)
      (expect "dark.normal.orange" "#e67f43" palettes.dark.normal.orange)
      (expect "dark.normal.violet" "#a580e2" palettes.dark.normal.violet)
    ])}
    touch $out
  ''
