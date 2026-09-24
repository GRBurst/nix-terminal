{
  description = "Home Manager configuration with the nix-terminal kit for a Coder workspace";

  # nixpkgs and home-manager come from nix-terminal, so the kit is used at
  # the revisions its checks ran against.
  inputs = {
    nix-terminal.url = "github:GRBurst/nix-terminal";
    nixpkgs.follows = "nix-terminal/nixpkgs";
    home-manager.follows = "nix-terminal/home-manager";
  };

  outputs = {
    nixpkgs,
    home-manager,
    nix-terminal,
    ...
  }: let
    system = "x86_64-linux";
    user = import ./user.nix;
  in {
    # The pinned CLI: `nix run .#home-manager -- switch --flake .` (S2).
    packages.${system}.home-manager = home-manager.packages.${system}.home-manager;

    homeConfigurations.${user.name} = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [
        nix-terminal.homeModules.default
        {
          home = {
            username = user.name;
            inherit (user) homeDirectory stateVersion;
          };
        }
        ./home.nix
      ];
    };
  };
}
