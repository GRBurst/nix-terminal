{
  pkgs,
  lib,
  ...
}: let
  style = import ../../lib/style {inherit lib;};
  light = (import ../../lib/style/enfocado.nix).light;
  dark = (import ../../lib/style/enfocado.nix).dark;
  rofi = style.mkRofiTheme light;
  zathuraLight = style.mkZathuraTheme light;
  zathuraDark = style.mkZathuraTheme dark;
  hypr = style.mkHyprlandTheme dark;
  swayDark = style.mkSwayTheme dark;
  swayLight = style.mkSwayTheme light;
  dunst = style.mkDunstConfig light {
    families.sansSerif.name = "X";
    sizes.notification.body = 11;
  };
  contains = needle: hay:
    if lib.hasInfix needle hay
    then null
    else throw "template missing literal: ${needle}";
in
  pkgs.runCommand "check-templates" {} ''
    ${builtins.toString (lib.filter (x: x != null) [
      (contains "muted: #878787" rofi)
      (contains "element selected {\n  background-color: @accent;" rofi)
      (contains "element-text, element-icon {\n  background-color: transparent;\n  text-color: inherit;" rofi)
      (contains "set default-bg \"#ffffff\"" zathuraLight)
      (contains "set default-fg \"#474747\"" zathuraLight)
      (contains "set default-bg \"#181818\"" zathuraDark)
      (contains "set highlight-active-color \"#368aeb\"" zathuraDark)
      (contains "rgba(368aebee)" hypr)
      (contains "rgba(a580e2ee)" hypr)
      (contains "rgba(3b3b3baa)" hypr)
      (contains "frame_color = \"#d04a00\"" dunst)
      # Sway reuses i3's client.* vocabulary; what is pinned here is the
      # palette mapping, not the syntax -- `sway-config-parses-*` runs the real
      # parser over the rendered result.
      (contains "client.focused          #368aeb" swayDark)
      (contains "client.urgent           #ed4a46" swayDark)
      (
        if swayLight != swayDark
        then null
        else throw "mkSwayTheme renders the same text for both palettes; the light/dark wiring is broken"
      )
    ])}
    touch $out
  ''
