# Architecture

## Goals and boundaries

- One Home Manager module, `homeModules.default`, with the options under
  `programs.terminalKit`. It is Home Manager only: no NixOS module, no
  `osConfig`, no Stylix option. The check `no-os-config` enforces the last two.
- Every package comes from the consumer's `pkgs`, so the consumer's nixpkgs
  configuration (overlays, CUDA, unfree policy) applies.
- Nothing personal is in this repository. Personal values (git identity,
  private aliases, private keymaps, private includes) enter through typed
  options, the *hooks*:
  `git.{name,email,signingKey,githubUser,extraAliases,includes,tigExtraConfig}`,
  `zsh.{extraAliases,extraInit,historyPath}`, `bash.extraAliases`,
  `nvf.extraKeymaps`, `yazi.flavorOverrides`, `aiSkills.skills`. The check
  `leaks` refuses e-mail addresses, key ids and personal home paths anywhere
  in the tree.

## Layout

```
flake.nix                   outputs; homeModules.default composes the kit
lib/style/                  palettes and renderers, pure ({lib} only)
modules/terminal-kit/       default.nix (options) + one file per feature
packages/alacritty-theme.nix
templates/coder/            flake.nix, user.nix (the only file to edit), home.nix
checks/                     lib.nix (test configurations) + one file per area
.github/workflows/check.yml CI: nix flake check --keep-going
```

## Module composition

`homeModules.default` is

```nix
{
  key = "nix-terminal#terminal-kit";
  imports = [nvf.homeManagerModules.default nix-index-database.homeModules.nix-index (import ./modules/terminal-kit {inherit inputs style;})];
}
```

The `key` makes a repeated import of the kit a no-op. nvf's module has no key
and fails when it is imported twice, so the kit imports it, and consumers must
not import it themselves.

`modules/terminal-kit/default.nix` declares the option tree and imports one
file per feature (`packages.nix`, `tools.nix`, `yazi.nix`, `git.nix`,
`env.nix`, `zsh.nix`, `bash.nix`, `integration.nix`, `nvf.nix`, `theme.nix`,
`clipboard.nix`, `ai-skills.nix`). Each file gates on `enable` and its own
switch; `yazi.flavorOverrides` is declared in `yazi.nix`, its only reader,
because its type needs `pkgs`. Hooks merge into the Home Manager attribute
sets, so a consumer's aliases render next to the kit's. The flake inputs and
`lib.style` reach the files through `_module.args` as `terminalKitInputs` and
`terminalKitStyle`.

Defaults: everything is on once `enable = true`, except the `dev` package set
(heavy, and its `nodejs` can shadow another Node.js) and agent skills. The
README's option table lists every leaf option; `readme-options` fails when a
leaf is missing from it or a row names something that is not a leaf option.

## Shell integration

- `owned`: Home Manager's usual files: `~/.zshenv` (zsh's `dotDir` is
  `~/.config/zsh`), `~/.bashrc`, `~/.profile`, `~/.bash_profile`.
- `sourced`: the rc files belong to someone else (a workspace image). The kit
  disables Home Manager's `~/.zshenv`, `~/.bash_profile` and `~/.profile`
  (`~/.bash_logout` is written only for a non-empty `logoutExtra`), sets
  zsh's `dotDir` to `~/.config/terminal-kit/zsh` and moves the generated
  `.bashrc` to `~/.config/terminal-kit/bash/bashrc`. The entry files
  `~/.config/terminal-kit/init.{zsh,bash}`:
  1. return at once if their guard variable (`__tk_zsh_loaded`,
     `__tk_bash_loaded`) is set; it is not exported, so a child shell runs
     its rc files again;
  2. source `~/.nix-profile/etc/profile.d/nix.sh` if `~/.nix-profile/bin` is
     not on `PATH`, and prepend the Home Manager profile's `bin` if it is
     still missing, so a nested shell adds nothing twice;
  3. source `hm-session-vars.sh` (guarded by Home Manager itself) and the
     generated rc file.

  They never source an image rc file (that would recurse through the
  one-time snippet) and never export `ZDOTDIR`. Terminal output in the zsh
  init (titles, cursor shape, `tput`) runs only when stdout is a terminal,
  and fzf's zsh integration loads only with a terminal on stdin; external
  commands used at start-up (`tput`, `grep`) are referenced by store path,
  because the image may lack them.
- The one-time snippet (PD13) is
  `if [ -r "$HOME/.config/terminal-kit/init.zsh" ]; then . "$HOME/.config/terminal-kit/init.zsh"; fi`,
  and the same for bash: exit status 0 when the entry file is missing (no
  `/nix` mount yet). The activation step `terminalKitSnippet` runs
  `terminal-kit-check-snippet`, which greps `~/.zshrc` and `~/.bashrc` for
  the entry path (not the whole line, so any spelling counts) and prints the
  snippet for a file that lacks it. It never writes image files and always
  exits 0.
- zsh history goes to `zsh.historyPath`, resolved at evaluation time
  (default `<XDG state home>/zsh/history`).

## Theme

- `lib.style` holds the enfocado light and dark palettes and renderers
  (alacritty TOML, yazi flavors, base16). It depends on `lib` only.
- The CLI tools use the 16 ANSI colours and follow the terminal: bat
  `ansi`, btop `TTY`, lazygit and fzf defaults.
- yazi gets `enfocado-light` and `enfocado-dark` flavors, with
  `yazi.flavorOverrides` merged in.
- Neovim: vim-enfocado (pinned revision), with
  `vim.g.enfocado_style = theme.nvf.enfocadoStyle`. The mode comes from
  `theme.modeSource`:
  - `file`: `$XDG_STATE_HOME/my-theme/mode` (`light`/`dark`, `light` when
    missing) decides; a `SIGUSR1` makes running instances reread it.
  - `terminal`: without a state file Neovim keeps the background it detects
    from the terminal (OSC 11) and reapplies enfocado when `background`
    changes; with a state file the file wins, also after a late terminal
    reply. `SIGUSR1` applies the state file if there is one.
- `nix-terminal-mode light|dark|auto` (installed only with `terminal`)
  writes the state file atomically (one word and a newline) or removes it,
  then sends `SIGUSR1` to the user's Neovim processes; any other argument
  exits 64. After `auto`, running instances keep their current mode; new
  ones follow the terminal.
- `packages.x86_64-linux.alacritty-theme-enfocado-{light,dark}` render the
  same palettes with `allowedReferences = []`, for a terminal on a machine
  without Nix.

## Clipboard

`clipboard = "system"` keeps the X11/Wayland clipboard: nvf's `xclip` and
`wl-copy` providers and the zsh-system-clipboard plugin.

`clipboard = "osc52"` registers a Lua clipboard provider in Neovim
(`registers = "unnamedplus"`): a copy to `+` or `*` is sent with Neovim's
OSC 52 encoder and cached; a paste returns the cache. No OSC 52 read query
is ever sent (many terminals do not answer one, and waiting would stall
every paste). zsh's `vi-yank`, `vi-yank-eol` and `vi-yank-whole-line`
widgets also write the cut buffer as OSC 52 to `/dev/tty`. No X11/Wayland
clipboard tool is installed; `closure-hygiene` checks the template's
closure for them and for GUI toolkits.

## Agent skills

`ai-skills.nix` links every entry of `aiSkills.skills` into
`~/.agents/skills/<name>` (read by opencode, pi, codex and agy) and
`~/.claude/skills/<name>` (Claude Code) as per-skill links, never as a
linked directory, so Claude Code keeps write access to its own skills
directory. The curated set (the 14 obra/superpowers skills, `xp-clean-code`,
`karpathy-guidelines`) is defined in `config`, not as the option default,
so a consumer's entries merge with it. An assertion requires a `SKILL.md`
in each source, and `ai-skills-inventory` compares the superpowers list
with the pinned upstream tree, so an input bump cannot add or drop a skill
silently.

## The template

`templates/coder` is a complete Home Manager flake. Its inputs follow
`nix-terminal`'s `nixpkgs` and `home-manager`, so a workspace runs the
revisions the checks ran against; it exposes that `home-manager` CLI as
`packages.x86_64-linux.home-manager` for the first switch. `user.nix` holds
the only edits (user name, home directory, state version). `Ct` in the
checks is built from the same `user.nix` and `home.nix`, and
`template-evaluates` asserts that the template flake's activation package is
`Ct`'s, so every check over `Ct` covers what a workspace builds.

## Checks

`nix flake check --keep-going`; each check fails at build time with a
message naming the offending value, so one run reports every failure. `Ct`
is the template, unedited (`sourced`, `osc52`); `Co` has every option on
(`owned`, user `tester`); `Cf` is `Co` with the `file` mode source.

| Area | Checks |
| --- | --- |
| Evaluation and option wiring (`Ct`, `Co`, `Cf`) | `configs-evaluate`, `packages-sets`, `tools`, `env`, `yazi-flavors`, `git-identity`, `git-clus`, `git-hooks`, `zsh-hooks`, `bash-aliases`, `history-path`, `nvf-extra-keymaps`, `nvf-file-mode`, `nvf-nix-lsp` |
| Sourced mode | `sourced-no-rc-files`, `sourced-shell-smoke` (silent start, tools and aliases resolve, nested shells, dangling entry file), `snippet-check`, `zsh-tty-guard`, `zsh-tput-pinned` |
| Theme | `nvf-theme-terminal`, `mode-command`, `mode-command-installed`, `mode-signal` |
| Clipboard | `clipboard-osc52-eval`, `clipboard-osc52-paste`, `zsh-osc52-plugins`, `zsh-osc52-encode`, `closure-hygiene` |
| Agent skills and Claude Code | `ai-skills-links`, `ai-skills-inventory`, `claude-noninterference` |
| The template flake, evaluated offline with this flake as `nix-terminal` | `template-evaluates`, `template-exposes-hm-cli` |
| Pure library and build output | `style-palette`, `style-templates`, `style-base16`, `alacritty-theme` (TOML round trip, no store path) |
| Repository and publication | `leaks`, `no-os-config`, `formatting` (Alejandra), `ci-workflow-lint` (actionlint), `outputs-shape` (exactly the documented output groups, MIT metadata, LICENSE), `readme-options`, `workspace-probe` (the phase-0 probe script: shellcheck, a scratch-`$HOME` run of `baseline` and `compare`) |

Runtime checks run shells and headless Neovim in a scratch `$HOME` inside
the build sandbox. Generated text is matched with `lib.hasInfix` or line
splitting, never with a wildcard regex (backtracking regexes do not
terminate on long inputs).

## Pinning

`flake.lock` pins nixpkgs, home-manager, nvf, nix-index-database and the
skill sources (superpowers, xp-clean-code, karpathy-skills). Consumers that
share inputs set `follows`; nix-index-database keeps its own nixpkgs.
