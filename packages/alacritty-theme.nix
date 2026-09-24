# Store-path-free enfocado themes for alacritty (R10), e.g. for a Windows
# alacritty that talks to the workspace over ssh.exe.
{
  pkgs,
  lib,
  style,
}: let
  palettes = style.palettes.enfocado;
  mk = v:
    pkgs.runCommand "alacritty-theme-enfocado-${v}" {
      text = style.mkAlacrittyTheme palettes.${v};
      passAsFile = ["text"];
      allowedReferences = [];
      meta = {
        license = lib.licenses.mit;
        description = "vim-enfocado ${v} colours for alacritty";
      };
    } ''
      mkdir -p $out
      cp "$textPath" $out/enfocado-${v}.toml
    '';
in {
  alacritty-theme-enfocado-light = mk "light";
  alacritty-theme-enfocado-dark = mk "dark";
}
