# `sourced` shell integration: entry files, no rc files.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf (cfg.enable && cfg.shellIntegration == "sourced") {};
}
