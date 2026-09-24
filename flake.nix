{
  description = "Terminal kit: zsh, git, Neovim (nvf) and CLI tools as a Home Manager module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # No `nixpkgs.follows`: mirrors the consuming private flake, whose
    # nix-index-database input keeps its own nixpkgs (PD4).
    nix-index-database.url = "github:nix-community/nix-index-database";
    superpowers = {
      url = "github:obra/superpowers";
      flake = false;
    };
    xp-clean-code = {
      url = "github:HivemindTechnologies/xp-clean-code";
      flake = false;
    };
    karpathy-skills = {
      url = "github:multica-ai/andrej-karpathy-skills";
      flake = false;
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    ...
  }: let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    pkgs = nixpkgs.legacyPackages.${system};
    style = import ./lib/style {inherit lib;};
  in {
    lib.style = style;

    packages.${system} = import ./packages/alacritty-theme.nix {inherit pkgs lib style;};

    homeModules.default = {
      # A stable key deduplicates the kit itself; nvf and nix-index-database
      # are imported here exactly once (PD3).
      key = "nix-terminal#terminal-kit";
      imports = [
        inputs.nvf.homeManagerModules.default
        inputs.nix-index-database.homeModules.nix-index
        (import ./modules/terminal-kit {inherit inputs style;})
      ];
    };

    # --- tmpl ---
    templates.coder = {
      path = ./templates/coder;
      description = "Terminal kit for a Coder workspace (sourced shell integration, OSC 52)";
      welcomeText = ''
        # nix-terminal: Coder workspace template
        1. Edit `user.nix` (user name, home directory, stateVersion) if the defaults do not fit.
        2. Switch: `nix run .#home-manager -- switch --flake .`
        3. Append the one-time snippet (see the README of github:GRBurst/nix-terminal)
           to `~/.zshrc` and `~/.bashrc`.
      '';
    };
    # --- end tmpl ---

    checks.${system} = import ./checks {inherit pkgs lib self inputs home-manager;};
    formatter.${system} = pkgs.alejandra;
  };
}
