# The general and dev package sets.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.packages.general.enable {
      home.packages = with pkgs; [
        htop
        iotop
        lsof
        wget
        ripgrep
        fd
        tree
        unzip
        zip
        file
        jq
      ];
    })

    (lib.mkIf cfg.packages.dev.enable {
      home.packages = with pkgs; [
        # neovim  # provided by nvf (programs.terminalKit.nvf)
        # gcc
        clang
        gnumake
        cmakeCurses
        nodejs
        docker-compose
        direnv
        devenv
      ];
      programs.devenv = {
        enable = true;
        enableZshIntegration = true;
      };
    })
  ]);
}
