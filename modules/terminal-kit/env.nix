# Public session variables.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      EDITOR = "nvim";
      SUDO_EDITOR = "nvim";
      VISUAL = "nvim";

      SBT_OPTS = "-Xms1G -Xmx4G -Xss16M";

      AUTOSSH_GATETIME = "0";
    };
  };
}
