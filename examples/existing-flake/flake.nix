{
  description = "An existing Home Manager flake with the nix-terminal kit added";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Added: the kit, on your nixpkgs and home-manager.
    nix-terminal = {
      url = "github:GRBurst/nix-terminal";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    nix-terminal,
    ...
  }: {
    homeConfigurations.tester = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        ./home.nix
        # Added: the kit (it imports nvf and nix-index-database itself).
        nix-terminal.homeModules.default
        {
          programs.terminalKit = {
            enable = true;
            shellIntegration = "sourced"; # the image keeps ~/.zshrc and ~/.bashrc
            clipboard = "osc52";
            theme.modeSource = "terminal";
            aiSkills.enable = true;
          };
        }
      ];
    };
  };
}
