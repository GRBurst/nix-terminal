# The terminal kit: option tree and the sub-modules that
# implement it. Every sub-module gates on `enable` and its own switch.
{
  inputs,
  style,
}: {
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption mkEnableOption types;
  on = description:
    mkOption {
      type = types.bool;
      default = true;
      inherit description;
    };
  aliases = description:
    mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {gs = "git status";};
      inherit description;
    };
in {
  imports = [
    ./packages.nix
    ./tools.nix
    ./yazi.nix
    ./git.nix
    ./env.nix
    ./zsh.nix
    ./bash.nix
    ./integration.nix
    ./nvf.nix
    ./theme.nix
    ./clipboard.nix
    ./ai-skills.nix
  ];

  # The flake inputs (skill sources) and the palette library, for the
  # sub-modules; prefixed so they cannot collide with a consumer's args.
  config._module.args = {
    terminalKitInputs = inputs;
    terminalKitStyle = style;
  };

  options.programs.terminalKit = {
    enable = mkEnableOption "the terminal kit";

    shellIntegration = mkOption {
      type = types.enum ["owned" "sourced"];
      default = "owned";
      description = ''
        `owned`: Home Manager owns the shell rc files. `sourced`: Home Manager
        writes only the entry files under ~/.config/terminal-kit/, which an
        existing ~/.zshrc and ~/.bashrc source with a one-time snippet.
      '';
    };

    clipboard = mkOption {
      type = types.enum ["system" "osc52"];
      default = "system";
      description = ''
        `system`: the X11/Wayland clipboard. `osc52`: yanks go to the
        terminal clipboard (copy only; pastes come from the last yank).
      '';
    };

    packages = {
      general.enable = on "the general CLI package set";
      dev.enable = mkEnableOption "the development package set (heavy; its nodejs can shadow another Node.js)";
    };

    tools =
      lib.genAttrs ["bat" "btop" "lazygit" "fzf" "starship" "zoxide" "direnv" "nixIndex"]
      (name: {enable = on name;});

    yazi.enable = on "yazi with the enfocado flavors";

    zsh = {
      enable = on "zsh";
      extraAliases = aliases "Aliases merged into programs.zsh.shellAliases.";
      extraInit = mkOption {
        type = types.lines;
        default = "";
        description = "Appended to programs.zsh.initContent, after the kit's own content.";
      };
      historyPath = mkOption {
        type = types.str;
        # Resolved at evaluation time: a shell variable here would be read
        # at run time, where it may be unset.
        default = "${config.xdg.stateHome}/zsh/history";
        defaultText = lib.literalExpression ''"''${config.xdg.stateHome}/zsh/history"'';
        description = "The zsh history file.";
      };
    };

    bash = {
      enable = on "bash";
      extraAliases = aliases "Aliases merged into programs.bash.shellAliases.";
    };

    git = {
      enable = on "git";
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "user.name; null writes no identity.";
      };
      email = mkOption {
        type = types.nullOr (types.strMatching "^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$");
        default = null;
        example = "tester@example.invalid";
        description = "user.email; null writes no identity.";
      };
      signingKey = mkOption {
        type = types.nullOr (types.strMatching "^[0-9A-Fa-f]{8,40}$");
        default = null;
        example = "DEADBEEF";
        description = ''
          OpenPGP key id used to sign commits and tags. Per host, because the key
          lives in that machine's gpg keyring. `null` leaves commits and tags
          unsigned.
        '';
      };
      githubUser = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "GitHub user for the `clus` alias; null omits the alias.";
      };
      extraAliases = aliases "Aliases merged into the git aliases.";
      includes = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Passed to programs.git.includes.";
      };
    };

    nvf = {
      enable = on "Neovim (nvf)";
      extraKeymaps = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Appended after the kit's keymaps.";
      };
    };

    theme = {
      enable = on "the enfocado theme";
      modeSource = mkOption {
        type = types.enum ["file" "terminal"];
        default = "terminal";
        description = ''
          `file`: the state file ($XDG_STATE_HOME/my-theme/mode) decides.
          `terminal`: the terminal background decides unless the state file
          exists.
        '';
      };
      nvf.enfocadoStyle = mkOption {
        type = types.str;
        default = "nature";
        description = "Value assigned to vim.g.enfocado_style.";
      };
    };

    aiSkills = {
      enable = mkEnableOption "agent skill links under ~/.agents/skills and ~/.claude/skills";
      skills = mkOption {
        type = types.attrsOf types.path;
        default = {};
        description = ''
          Skill directories (each containing SKILL.md) by name. The kit's
          curated set is defined in config, so entries added here merge
          with it.
        '';
      };
    };
  };
}
