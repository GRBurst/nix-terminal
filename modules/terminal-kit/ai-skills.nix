# Agent skill links.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf (cfg.enable && cfg.aiSkills.enable) {};
}
