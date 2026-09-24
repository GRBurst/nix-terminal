# Neovim through nvf.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.terminalKit;
  # Consumer keymaps come after the kit's (PD12).
  appendExtraKeymaps = kitKeymaps: kitKeymaps ++ cfg.nvf.extraKeymaps;
in {
  config = lib.mkIf (cfg.enable && cfg.nvf.enable) {
    programs.nvf = {
      enable = true;
      defaultEditor = true;
      settings = {
        vim = {
          # --- Core ---
          viAlias = true;
          vimAlias = true;
          lineNumberMode = "number";
          searchCase = "smart";
          undoFile.enable = true;

          # `vim.clipboard` is set in clipboard.nix, per `clipboard` mode.

          # --- Theme ---
          theme = {
            enable = false;
          };

          # --- Options ---
          options = {
            expandtab = true;
            tabstop = 4;
            shiftwidth = 4;
            softtabstop = 4;
            shiftround = true;
            scrolloff = 5;
            sidescrolloff = 10;
            sidescroll = 1;
            wrap = false;
            linebreak = true;
            breakindent = true;
            breakindentopt = "shift:2";
            listchars = "tab:⊳\\ ,trail:·";
            list = true;
            virtualedit = "block,onemore";
            startofline = false;
            gdefault = true;
            confirm = true;
            cursorline = true;
            inccommand = "nosplit";
            display = "lastline,uhex";
            wildmode = "list:longest,full";
            lazyredraw = true;
            mouse = "a";
          };

          # --- LSP ---
          lsp = {
            enable = true;
            formatOnSave = true;
            inlayHints.enable = true;
            lightbulb.enable = true;
            mappings = {
              goToDefinition = "gd";
              listReferences = "gr";
            };
          };

          # --- Languages ---
          languages = {
            enableFormat = true;
            enableTreesitter = true;
            enableExtraDiagnostics = true;

            nix.enable = true;
            typescript.enable = true;
            json.enable = true;
            python.enable = true;
            bash.enable = true;
            sql.enable = true;
            rust.enable = true;
            css.enable = true;
            html.enable = true;
            markdown = {
              enable = true;
              format.type = ["prettier"];
            };
            lua.enable = true;
          };

          # --- File Tree ---
          filetree.neo-tree.enable = true;

          # --- Finder ---
          fzf-lua.enable = true;

          # --- Terminal ---
          terminal.toggleterm.enable = true;

          # --- Statusline & Tabline ---
          mini.statusline.enable = true;
          mini.tabline.enable = true;

          # --- Autocomplete ---
          autocomplete.blink-cmp.enable = true;

          # --- Utility ---
          utility = {
            surround.enable = true;
            snacks-nvim = {
              enable = true;
              setupOpts.indent.enabled = true;
            };
          };

          # --- Comments ---
          comments.comment-nvim.enable = true;

          # --- Visuals ---
          visuals = {
            nvim-scrollbar.enable = true;
            fidget-nvim.enable = true;
            nvim-web-devicons.enable = true;
            nvim-cursorline.enable = true;
          };

          # --- UI ---
          ui.illuminate.enable = true;

          # --- Binds ---
          binds = {
            whichKey = {
              enable = true;
              setupOpts.delay = 500;
            };
            cheatsheet.enable = true;
          };

          # --- Git ---
          git = {
            enable = true;
            gitsigns.enable = true;
          };

          # --- Extra Plugins ---
          extraPlugins = {
            vim-repeat.package = pkgs.vimPlugins.vim-repeat;
            vim-speeddating.package = pkgs.vimPlugins.vim-speeddating;
            vim-visual-multi.package = pkgs.vimPlugins.vim-visual-multi;
            vim-easy-align.package = pkgs.vimPlugins.vim-easy-align;
            vim-fugitive.package = pkgs.vimPlugins.vim-fugitive;
            vim-suda.package = pkgs.vimPlugins.vim-suda;
            undotree.package = pkgs.vimPlugins.undotree;
            switch-vim = {
              package = pkgs.vimPlugins.switch-vim;
              after = [
                ''
                  vim.g.switch_custom_definitions = {
                    { "on", "off" },
                    { "==", "!=" },
                    { "true", "false" },
                    { "yes", "no" },
                    { "YES", "NO" },
                    { "and", "or" },
                    { "if", "unless" },
                    { "first", "last" },
                    { "max", "min" },
                    { "left", "right" },
                    { "top", "bottom" },
                    { "up", "down" },
                    { "before", "after" },
                    { "show", "hide" },
                    { "add", "remove" },
                    { "even", "odd" },
                    { "class", "object", "trait" },
                  }
                ''
              ];
            };
          };

          # --- Autocmds ---
          autocmds = [
            {
              event = ["TermClose"];
              pattern = ["*"];
              command = "if !v:event.status | exe 'bdelete! '..expand('<abuf>') | endif";
            }
            {
              event = ["BufReadPost"];
              pattern = ["*"];
              command = ''if line("'\"") >= 1 && line("'\"") <= line("$") && &ft !~# 'commit' | exe "normal! g`\"" | endif'';
            }
            {
              event = ["BufEnter"];
              pattern = ["*"];
              command = "set noreadonly";
            }
            {
              event = ["BufEnter"];
              pattern = ["*"];
              command = "silent! lcd %:p:h";
            }
            {
              event = ["FileType"];
              pattern = ["text"];
              command = "setlocal textwidth=78";
            }
            {
              event = ["FileType"];
              pattern = ["scala"];
              command = "setlocal expandtab tabstop=2 shiftwidth=2 softtabstop=2";
            }
            {
              event = ["FileType"];
              pattern = ["typescript" "typescript.tsx"];
              command = "setlocal expandtab tabstop=2 shiftwidth=2 softtabstop=2";
            }
            {
              event = ["FileType"];
              pattern = ["gitcommit"];
              command = "setlocal spell";
            }
            {
              event = ["FileType"];
              pattern = ["sql"];
              command = "setlocal commentstring=--\\ %s";
            }
          ];

          # --- Keymaps ---
          keymaps = appendExtraKeymaps [
            # === NEO: Save/Quit/Buffer ===
            {
              mode = ["n"];
              key = "ö";
              action = "<cmd>update<cr>";
              desc = "Save";
            }
            {
              mode = ["v"];
              key = "ö";
              action = "<esc><cmd>update<cr>gv";
              desc = "Save (visual)";
            }
            {
              mode = ["n"];
              key = "Ö";
              action = "<cmd>w suda://%<cr>";
              desc = "Sudo save";
            }
            {
              mode = ["v"];
              key = "Ö";
              action = "<esc><cmd>w suda://%<cr>gv";
              desc = "Sudo save (visual)";
            }
            {
              mode = ["n" "v"];
              key = "ä";
              action = "<cmd>q<cr>";
              desc = "Quit";
            }
            {
              mode = ["n" "v"];
              key = "ü";
              action = "<cmd>bd<cr>";
              desc = "Delete buffer";
            }
            {
              mode = ["n" "v"];
              key = "<leader>ü";
              action = "<cmd>lua delete_other_buffers()<cr>";
              desc = "Delete other buffers";
            }

            # === NEO: Buffer Navigation ===
            {
              mode = ["n" "v"];
              key = "l";
              action = "<cmd>bnext<cr>";
              desc = "Next buffer";
            }
            {
              mode = ["n" "v"];
              key = "L";
              action = "<cmd>bprev<cr>";
              desc = "Prev buffer";
            }

            # === NEO: Window Navigation (math symbols) ===
            {
              mode = ["n" "v"];
              key = "∫";
              action = "<C-W>h";
              desc = "Window left";
            }
            {
              mode = ["n" "v"];
              key = "∀";
              action = "<C-W>j";
              desc = "Window down";
            }
            {
              mode = ["n" "v"];
              key = "Λ";
              action = "<C-W>k";
              desc = "Window up";
            }
            {
              mode = ["n" "v"];
              key = "∃";
              action = "<C-W>l";
              desc = "Window right";
            }
            {
              mode = ["i"];
              key = "∫";
              action = "<C-o><C-W>h";
              desc = "Window left (insert)";
            }
            {
              mode = ["i"];
              key = "∀";
              action = "<C-o><C-W>j";
              desc = "Window down (insert)";
            }
            {
              mode = ["i"];
              key = "Λ";
              action = "<C-o><C-W>k";
              desc = "Window up (insert)";
            }
            {
              mode = ["i"];
              key = "∃";
              action = "<C-o><C-W>l";
              desc = "Window right (insert)";
            }

            # === NEO: Highlight ===
            {
              mode = ["n"];
              key = "h";
              action = "<cmd>lua HighlightCurrentWord()<cr>";
              desc = "Highlight word";
            }

            # === NEO: Marks (swap M/m) ===
            {
              mode = ["n" "v"];
              key = "j";
              action = "`";
              desc = "Jump to mark";
            }
            {
              mode = ["n" "v"];
              key = "M";
              action = "m";
              desc = "Set mark";
            }
            {
              mode = ["n" "v"];
              key = "m";
              action = "`";
              desc = "Jump to mark";
            }
            {
              mode = ["n"];
              key = "<leader>j";
              action = "<C-]>";
              desc = "Jump to tag";
            }

            # === NEO: Macros ===
            {
              mode = ["n" "v"];
              key = "ß";
              action = "@q";
              desc = "Replay macro q";
            }
            {
              mode = ["n" "v"];
              key = "Q";
              action = "@f";
              desc = "Replay macro f";
            }

            # === NEO: Spelling ===
            {
              mode = ["n"];
              key = "k";
              action = "1z=";
              desc = "Spell suggestion";
            }
            {
              mode = ["n"];
              key = "K";
              action = "zg";
              desc = "Add to spellfile";
            }
            {
              mode = ["n"];
              key = "<C-h>";
              action = "]s";
              desc = "Next misspelled";
            }
            {
              mode = ["n"];
              key = "<C-k>";
              action = "[s";
              desc = "Prev misspelled";
            }

            # === Vim Fixes ===
            {
              mode = ["n"];
              key = "Y";
              action = "y$";
              desc = "Yank to EOL";
            }
            {
              mode = ["v"];
              key = "p";
              action = "pgvy";
              desc = "Paste keep register";
            }
            {
              mode = ["n"];
              key = "<leader>p";
              action = "v$<Left>pgvy";
              desc = "Paste over rest of line";
            }
            {
              mode = ["v"];
              key = "<";
              action = "<gv";
              desc = "Indent left keep sel";
            }
            {
              mode = ["v"];
              key = ">";
              action = ">gv";
              desc = "Indent right keep sel";
            }
            {
              mode = ["v"];
              key = "=";
              action = "=gv";
              desc = "Re-indent keep sel";
            }
            {
              mode = ["n"];
              key = "db";
              action = "xdb";
              desc = "Delete word back fix";
            }
            {
              mode = ["n"];
              key = "cb";
              action = "xcb";
              desc = "Change word back fix";
            }
            {
              mode = ["n" "v"];
              key = "\\";
              action = "?";
              desc = "Backward search";
            }

            # === Navigation ===
            {
              mode = ["n"];
              key = "go";
              action = "<C-o>";
              desc = "Jump back";
            }
            {
              mode = ["n"];
              key = "gi";
              action = "<C-i>";
              desc = "Jump forward";
            }
            {
              mode = ["n" "v"];
              key = "<C-Up>";
              action = "g<Up>";
              desc = "Wrapped line up";
            }
            {
              mode = ["n" "v"];
              key = "<C-Down>";
              action = "g<Down>";
              desc = "Wrapped line down";
            }
            {
              mode = ["i"];
              key = "<C-Up>";
              action = "<Esc>g<Up>";
              desc = "Wrapped line up (insert)";
            }
            {
              mode = ["i"];
              key = "<C-Down>";
              action = "<Esc>g<Down>";
              desc = "Wrapped line down (insert)";
            }

            # === Leader Commands ===
            {
              mode = ["n"];
              key = "<leader>m";
              action = "<cmd>make<cr>";
              desc = "Make";
            }
            {
              mode = ["n"];
              key = "<leader>n";
              action = "<cmd>lua smart_diagnostic_goto()<cr>";
              desc = "Next diagnostic (smart)";
            }
            {
              mode = ["n"];
              key = "<leader>N";
              action = "<cmd>lprev<cr>";
              desc = "Location prev";
            }
            {
              mode = ["n"];
              key = "<leader>ts";
              action = "<cmd>setlocal spell! spell?<cr>";
              desc = "Toggle spell";
            }
            {
              mode = ["n"];
              key = "<leader>th";
              action = "<cmd>lua AutoHighlightToggle()<cr>";
              desc = "Toggle auto-highlight";
            }
            {
              mode = ["n"];
              key = "<leader>wc";
              action = "g<c-g>";
              desc = "Word count";
            }
            {
              mode = ["n"];
              key = "<leader><leader>";
              action = "<cmd>nohlsearch<cr>";
              desc = "Clear highlight";
            }
            {
              mode = ["n"];
              key = "<leader>/";
              action = "<cmd>nohlsearch<cr>";
              desc = "Clear highlight";
            }
            {
              mode = ["i"];
              key = "<C-t>";
              action = "// TODO: ";
              desc = "Insert TODO";
            }

            # === Toggle End Char ===
            {
              mode = ["n"];
              key = "<leader>;";
              action = "<cmd>lua toggle_char_at_eol(';')<cr>";
              desc = "Toggle ;";
            }
            {
              mode = ["n"];
              key = "<leader>,";
              action = "<cmd>lua toggle_char_at_eol(',')<cr>";
              desc = "Toggle ,";
            }
            {
              mode = ["n"];
              key = "<leader>.";
              action = "<cmd>lua toggle_char_at_eol('.')<cr>";
              desc = "Toggle .";
            }
            {
              mode = ["n"];
              key = "<leader>:";
              action = "<cmd>lua toggle_char_at_eol(':')<cr>";
              desc = "Toggle :";
            }

            # === Surround ===
            {
              mode = ["n"];
              key = "S";
              action = "ys";
              desc = "Surround";
            }

            # === FZF ===
            {
              mode = ["n"];
              key = "<leader>e";
              action = "<cmd>FzfLua files<cr>";
              desc = "Find files";
            }
            {
              mode = ["n"];
              key = "<leader>E";
              action = "<cmd>FzfLua git_files<cr>";
              desc = "Git files";
            }
            {
              mode = ["n"];
              key = "<leader>r";
              action = "<cmd>FzfLua oldfiles<cr>";
              desc = "Recent files";
            }
            {
              mode = ["n"];
              key = "<leader>a";
              action = "<cmd>FzfLua live_grep<cr>";
              desc = "Live grep";
            }
            {
              mode = ["n"];
              key = "<leader>t";
              action = "<cmd>FzfLua tags<cr>";
              desc = "Tags";
            }

            # === Git ===
            {
              mode = ["n"];
              key = "<leader>gn";
              action = "<cmd>Gitsigns next_hunk<cr>";
              desc = "Next hunk";
            }
            {
              mode = ["n"];
              key = "<leader>gN";
              action = "<cmd>Gitsigns prev_hunk<cr>";
              desc = "Prev hunk";
            }
            {
              mode = ["n"];
              key = "<leader>ga";
              action = "<cmd>Gitsigns stage_hunk<cr>";
              desc = "Stage hunk";
            }
            {
              mode = ["n"];
              key = "<leader>gu";
              action = "<cmd>Gitsigns stage_hunk<cr>";
              desc = "Stage hunk";
            }
            {
              mode = ["n"];
              key = "<leader>gr";
              action = "<cmd>Gitsigns reset_hunk<cr>";
              desc = "Reset hunk";
            }
            {
              mode = ["n"];
              key = "<leader>gs";
              action = "<cmd>nohlsearch<cr><cmd>term tig status<cr>i";
              desc = "Tig status";
            }

            # === Plugins ===
            {
              mode = ["n"];
              key = "<leader>tu";
              action = "<cmd>UndotreeToggle<cr>";
              desc = "Toggle undotree";
            }
            {
              mode = ["n"];
              key = "<leader>o";
              action = "<cmd>Neotree toggle<cr>";
              desc = "Toggle file tree";
            }
            {
              mode = ["n" "v"];
              key = "∂";
              action = "<cmd>ToggleTerm direction=horizontal<cr>";
              desc = "Toggle terminal";
            }

            # === LSP ===
            {
              mode = ["n"];
              key = "gd";
              action = "<cmd>lua smart_goto_definition()<cr>";
              desc = "Go to definition";
            }
            {
              mode = ["n"];
              key = "gy";
              action = "<cmd>lua vim.lsp.buf.type_definition()<cr>";
              desc = "Type definition";
            }
            {
              mode = ["n"];
              key = "<leader>rn";
              action = "<cmd>lua vim.lsp.buf.rename()<cr>";
              desc = "Rename";
            }
            {
              mode = ["n"];
              key = "<leader>ac";
              action = "<cmd>lua vim.lsp.buf.code_action()<cr>";
              desc = "Code action";
            }
            {
              mode = ["n"];
              key = "<leader>f";
              action = "<cmd>lua vim.lsp.buf.format()<cr>";
              desc = "Format";
            }
            {
              mode = ["n"];
              key = "[g";
              action = "<cmd>lua vim.diagnostic.goto_prev()<cr>";
              desc = "Prev diagnostic";
            }
            {
              mode = ["n"];
              key = "]g";
              action = "<cmd>lua vim.diagnostic.goto_next()<cr>";
              desc = "Next diagnostic";
            }

            # === Config Quick Access ===
            {
              mode = ["n"];
              key = "<leader>vr";
              action = "<cmd>FzfLua oldfiles<cr>";
              desc = "Recent files";
            }
          ];

          # --- Lua Config ---
          luaConfigRC.custom-functions = lib.mkBefore ''
            -- Smart Home: toggle between col 0 and first non-blank
            vim.keymap.set("n", "<Home>", function()
              return vim.fn.col(".") == vim.fn.match(vim.fn.getline("."), "\\S") + 1 and "0" or "^"
            end, { expr = true, silent = true })
            vim.keymap.set("i", "<Home>", function()
              return vim.fn.col(".") == vim.fn.match(vim.fn.getline("."), "\\S") + 1 and "<Home>" or "<C-O>^"
            end, { expr = true, silent = true })

            -- Toggle character at end of line
            function toggle_char_at_eol(target_char)
              local line_content = vim.api.nvim_get_current_line()
              if line_content:sub(-1) == target_char then
                vim.api.nvim_set_current_line(line_content:sub(1, -2))
              else
                vim.api.nvim_set_current_line(line_content .. target_char)
              end
            end

            -- Delete all buffers except current
            function delete_other_buffers()
              local current_buf = vim.api.nvim_get_current_buf()
              for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if buf ~= current_buf and vim.api.nvim_buf_is_loaded(buf) then
                  pcall(vim.api.nvim_buf_delete, buf, { force = false })
                end
              end
            end

            -- Smart diagnostic goto (errors > warnings > any)
            function smart_diagnostic_goto()
              local sev = vim.diagnostic.severity
              local has = function(s) return next(vim.diagnostic.get(0, { severity = s })) ~= nil end
              local s = has(sev.ERROR) and sev.ERROR or has(sev.WARN) and sev.WARN or nil
              vim.diagnostic.goto_next({ severity = s, float = true })
            end

            -- Smart goto definition (LSP if available, else vim gd)
            function smart_goto_definition()
              if next(vim.lsp.get_clients({ bufnr = 0 })) then
                vim.lsp.buf.definition()
              else
                vim.cmd("normal! gd")
              end
            end

            -- Highlight current word (toggle)
            local highlighting = false
            function HighlightCurrentWord()
              local word = vim.fn.expand("<cword>")
              local pattern = "\\C\\<" .. word .. "\\>"
              if highlighting and vim.fn.getreg("/") == pattern then
                highlighting = false
                vim.cmd("nohlsearch")
              else
                vim.fn.setreg("/", pattern)
                highlighting = true
                vim.cmd("set hlsearch")
              end
            end

            -- AutoHighlight toggle (highlight word under cursor on idle)
            local auto_hl_group = nil
            function AutoHighlightToggle()
              vim.fn.setreg("/", "")
              if auto_hl_group then
                vim.api.nvim_del_augroup_by_id(auto_hl_group)
                auto_hl_group = nil
                vim.o.updatetime = 4000
                print("Highlight current word: off")
              else
                auto_hl_group = vim.api.nvim_create_augroup("auto_highlight", { clear = true })
                vim.api.nvim_create_autocmd("CursorHold", {
                  group = auto_hl_group,
                  pattern = "*",
                  callback = function()
                    local w = vim.fn.expand("<cword>")
                    vim.fn.setreg("/", "\\V\\<" .. vim.fn.escape(w, "\\") .. "\\>")
                  end,
                })
                vim.o.updatetime = 200
                print("Highlight current word: ON")
              end
            end

            -- Highlight visual selection
            vim.keymap.set("v", "h", function()
              vim.cmd("normal! gvy")
              local sel = vim.fn.getreg('"')
              local pat = vim.fn.escape(sel, "\\/")
              pat = pat:gsub("\n", "\\n")
              vim.fn.setreg("/", "\\V" .. pat)
              vim.cmd("set hlsearch")
            end, { silent = true, desc = "Highlight selection" })
          '';
        };
      };
    };
  };
}
