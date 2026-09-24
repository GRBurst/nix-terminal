# The clipboard, per `clipboard` mode (R15).
{
  config,
  lib,
  ...
}: let
  cfg = config.programs.terminalKit;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # `system`: Neovim uses the X11/Wayland clipboard.
    (lib.mkIf (cfg.nvf.enable && cfg.clipboard == "system") {
      programs.nvf.settings.vim.clipboard = {
        enable = true;
        providers.xclip.enable = true;
        providers.wl-copy.enable = true;
        registers = "unnamedplus";
      };
    })

    # `osc52`: OSC 52 copy-only clipboard.
    (lib.mkIf (cfg.clipboard == "osc52") {})
  ]);
}
