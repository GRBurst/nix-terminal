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
