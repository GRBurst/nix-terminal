# `sourced` shell integration: entry files, no rc files (R5).
#
# Home Manager writes nothing at the image's rc files. The existing
# ~/.zshrc and ~/.bashrc source the entry files with a one-time snippet
# (PD13):
#   if [ -r "$HOME/.config/terminal-kit/init.zsh" ]; then . "$HOME/.config/terminal-kit/init.zsh"; fi
# Entry files never source an image file (K11), never export ZDOTDIR, and
# are re-entrant through a guard that is not exported, so a child shell
# runs its rc files again.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.terminalKit;
  # Home-relative, because the one-time snippet names it as $HOME/…
  entryDir = ".config/terminal-kit";
  home = config.home.homeDirectory;
  dotDir = "${home}/${entryDir}/zsh";
  bashrc = "${entryDir}/bash/bashrc";
  # R7: prints the one-time snippet for each rc file that lacks it; never
  # writes. The entry path is what counts, not the whole line (PD13).
  checkSnippet = pkgs.writeShellApplication {
    name = "terminal-kit-check-snippet";
    runtimeInputs = [pkgs.gnugrep];
    text = ''
      for sh in zsh bash; do
        rc="$HOME/.''${sh}rc"; entry="${entryDir}/init.$sh"
        if ! grep -qF "$entry" "$rc" 2>/dev/null; then
          # shellcheck disable=SC2016 # $HOME is printed literally, for pasting
          printf 'terminal-kit: append this line to %s:\n  if [ -r "$HOME/%s" ]; then . "$HOME/%s"; fi\n' "$rc" "$entry" "$entry"
        fi
      done
      exit 0
    '';
  };
  sessionVars = "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh";
  profileBin = "${config.home.profileDirectory}/bin";

  entry = {
    guard,
    rc,
  }: ''
    # terminal-kit entry (sourced mode). Generated; do not edit.
    [[ -n ''${${guard}-} ]] && return 0
    ${guard}=1
    case ":$PATH:" in
      *":$HOME/.nix-profile/bin:"*) ;;
      *) if [[ -r "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then . "$HOME/.nix-profile/etc/profile.d/nix.sh"; fi ;;
    esac
    # The Home Manager profile's bin, when no nix.sh put it on PATH.
    case ":$PATH:" in
      *":${profileBin}:"*) ;;
      *) PATH="${profileBin}:$PATH" ;;
    esac
    . "${sessionVars}"
    . "${rc}"
  '';
in {
  config = lib.mkIf (cfg.enable && cfg.shellIntegration == "sourced") {
    # zsh.nix sets dotDir at normal priority for `owned`.
    programs.zsh.dotDir = lib.mkForce dotDir;

    home.packages = [checkSnippet];
    home.activation.terminalKitSnippet =
      lib.hm.dag.entryAfter ["writeBoundary"] "${lib.getExe checkSnippet}";

    home.file = {
      ".zshenv".enable = lib.mkForce false;
      ".bashrc".target = bashrc;
      ".bash_profile".enable = lib.mkForce false;
      ".profile".enable = lib.mkForce false;
      # .bash_logout: Home Manager writes it only for logoutExtra != "".

      "${entryDir}/init.zsh".text = entry {
        guard = "__tk_zsh_loaded";
        rc = "${dotDir}/.zshrc";
      };
      "${entryDir}/init.bash".text = entry {
        guard = "__tk_bash_loaded";
        rc = "${home}/${bashrc}";
      };
    };
  };
}
