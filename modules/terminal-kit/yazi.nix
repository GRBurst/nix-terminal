# yazi with the enfocado flavors.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf (cfg.enable && cfg.yazi.enable) {};
}
