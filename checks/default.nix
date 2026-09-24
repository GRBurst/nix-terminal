{
  pkgs,
  lib,
  self,
  inputs,
  home-manager,
}: let
  tk = import ./lib.nix {inherit pkgs lib self home-manager;};
in
  import ./eval.nix {inherit pkgs self tk;}
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

    # --- misc (T6.2, T8.1) -------------------------------------------
    mode-command = import ./mode-command.nix {
      inherit pkgs lib;
      inherit (tk) Ct;
    };
    # --- end misc ----------------------------------------------------

    # --- sourced (group 5, T7.3) ---
    sourced-shell-smoke = import ./shell-smoke.nix {
      inherit pkgs lib;
      inherit (tk) templateHome;
    };
    # --- end sourced ---
  }
