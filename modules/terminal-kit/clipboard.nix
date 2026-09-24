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

    # `osc52`: copy-only (D19). `+` and `*` are written to the terminal
    # clipboard; a paste returns Neovim's own last yank, so no OSC 52 read
    # query is ever sent (a terminal that ignores it would block `p` for
    # 10 s). A Lua-function provider is asked on every paste, hence the
    # cache. No X11/Wayland clipboard tool is installed (R13).
    (lib.mkIf (cfg.nvf.enable && cfg.clipboard == "osc52") {
      programs.nvf.settings.vim = {
        clipboard = {
          enable = true;
          providers = lib.genAttrs ["wl-copy" "xclip" "xsel"] (_: {enable = false;});
          registers = "unnamedplus";
        };
        luaConfigRC.terminal-kit-clipboard = ''
          local osc52 = require("vim.ui.clipboard.osc52")
          local cache = { ["+"] = { { "" }, "v" }, ["*"] = { { "" }, "v" } }
          local function copy(reg)
            local send = osc52.copy(reg)
            return function(lines, regtype)
              cache[reg] = { lines, regtype }
              pcall(send, lines, regtype)
            end
          end
          local function from_cache(reg)
            return function()
              return cache[reg]
            end
          end
          vim.g.clipboard = {
            name = "terminal-kit-osc52",
            copy = { ["+"] = copy("+"), ["*"] = copy("*") },
            paste = { ["+"] = from_cache("+"), ["*"] = from_cache("*") },
          }
        '';
      };
    })
  ]);
}
