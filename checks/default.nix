{
  pkgs,
  lib,
  self,
  inputs,
  home-manager,
}:
import ./eval.nix {inherit pkgs self;}
// {
  leaks = import ./leaks {inherit pkgs self;};

  # Moved unchanged from the consuming flake; only the import paths differ.
  style-palette = pkgs.callPackage ./style/palette.nix {};
  style-templates = pkgs.callPackage ./style/templates.nix {};
  style-base16 = pkgs.callPackage ./style/base16.nix {};

  alacritty-theme = import ./alacritty-theme.nix {
    inherit pkgs lib;
    inherit (self.lib) style;
    packages = self.packages.${pkgs.stdenv.hostPlatform.system};
  };

  # Every `.nix` file in the tree is Alejandra-formatted.
  formatting = pkgs.runCommand "formatting" {nativeBuildInputs = [pkgs.alejandra];} ''
    cd ${self}
    alejandra --check . || {
      echo "formatting: run alejandra on the files above" >&2
      exit 1
    }
    touch $out
  '';
}
