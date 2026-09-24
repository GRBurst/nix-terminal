{
  pkgs,
  lib,
  self,
  inputs,
  home-manager,
}: {
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
