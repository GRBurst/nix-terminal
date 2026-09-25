# bat, btop, lazygit, fzf, starship, zoxide, direnv, nix-index; each behind cfg.tools.<name>.enable.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
  on = name: cfg.enable && cfg.tools.${name}.enable;
in {
  config = lib.mkMerge [
    # The terminal tools use the 16 ANSI colours, which follow the
    # terminal's own light/dark palette.
    (lib.mkIf (on "bat") {
      programs.bat = {
        enable = true;
        config.theme = "ansi";
      };
    })

    (lib.mkIf (on "btop") {
      programs.btop = {
        enable = true;
        settings = {
          color_theme = "TTY";
          theme_background = false;
          # btop rewrites btop.conf on exit; Home Manager's copy is a
          # read-only store link, so saving would fail every time.
          save_config_on_exit = false;
        };
      };
    })

    # lazygit defaults to terminal colours already.
    (lib.mkIf (on "lazygit") {programs.lazygit.enable = true;})

    (lib.mkIf (on "direnv") {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        enableZshIntegration = true;
      };
    })
    (lib.mkIf (on "fzf") {
      programs.fzf = {
        enable = true;
        # Home Manager's zsh integration (same order and text, plus the
        # stdin test): without a terminal on stdin, `fzf --zsh` fails to
        # restore the `zle` option and prints "can't change option: zle"
        # at every start (R5).
        enableZshIntegration = false;
      };
      # The block below is adapted from Home Manager modules/programs/fzf.nix,
      # MIT, Copyright (c) Home Manager contributors.
      programs.zsh.initContent = lib.mkOrder 910 ''
        if [[ $options[zle] = on && -t 0 ]]; then
          source <(${lib.getExe config.programs.fzf.package} --zsh)
        fi
      '';
    })
    (lib.mkIf (on "nixIndex") {
      programs.nix-index = {
        enable = true;
        enableZshIntegration = true;
      };
    })
    # nix-index-database's module turns nix-index on by default; off here
    # means off, unless the consumer sets it explicitly.
    (lib.mkIf (!on "nixIndex") {
      programs.nix-index.enable = lib.mkOverride 900 false;
    })
    (lib.mkIf (on "zoxide") {
      programs.zoxide = {
        enable = true;
        enableZshIntegration = true;
      };
    })

    (lib.mkIf (on "starship") {
      programs.starship = {
        # https://starship.rs/config/
        enable = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
        enableFishIntegration = true;
        enableIonIntegration = true;
        settings =
          # (
          #   with builtins; fromTOML (readFile "${pkgs.starship}/share/starship/presets/nerd-font-symbols.toml")
          # )
          # // {
          {
            git_status.stashed = ""; # disable stash indicator
            gcloud.disabled = true;
            python.disabled = true;
            rust.disabled = true;
            scala.disabled = true;
            java.disabled = true;
            julia.disabled = true;
            docker_context.disabled = true;
            dart.disabled = true;
            package.disabled = true; # do not show npm, cargo etc
            nodejs.disabled = true;
            c.disabled = true;
            cpp.disabled = true;
          };
      };
    })
  ];
}
