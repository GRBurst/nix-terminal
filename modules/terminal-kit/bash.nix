# bash.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf (cfg.enable && cfg.bash.enable) {
    programs.bash.enable = true; # Bash enabled for safety
    programs.bash.shellAliases = cfg.bash.extraAliases;
  };
}
