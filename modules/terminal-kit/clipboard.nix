# OSC 52 copy-only clipboard.
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf (cfg.enable && cfg.clipboard == "osc52") {};
}
