# Architecture

> **Draft.** Parts marked *(planned)* describe the intended design; the
> module does not implement them yet.

## Goals and boundaries

- One Home Manager module, `homeModules.default`, with the options under
  `programs.terminalKit`. It is Home Manager only: no NixOS module, no
  `osConfig`, no Stylix option. The check `no-os-config` enforces the last two.
- Every package comes from the consumer's `pkgs`, so the consumer's nixpkgs
  configuration (overlays, CUDA, unfree policy) applies.
- Nothing personal is in this repository. Personal values (git identity,
  private aliases, private keymaps, private includes) enter through typed
  options, the *hooks*: `git.{name,email,signingKey,githubUser,extraAliases,includes}`,
  `zsh.{extraAliases,extraInit,historyPath}`, `bash.extraAliases`,
  `nvf.extraKeymaps`. The check `leaks` refuses e-mail addresses, key ids
  and personal home paths anywhere in the tree.

## Layout

```
flake.nix                   outputs; homeModules.default composes the kit
lib/style/                  palettes and renderers, pure ({lib} only)
modules/terminal-kit/       default.nix (options) + one file per feature
packages/alacritty-theme.nix
templates/coder/            flake.nix, user.nix (the only file to edit), home.nix
checks/                     lib.nix (test configurations), eval.nix, leaks/, style/
.github/workflows/check.yml CI: nix flake check --keep-going
```

## Module composition

`homeModules.default` is

```nix
{
  key = "nix-terminal#terminal-kit";
  imports = [nvf.homeManagerModules.default nix-index-database.homeModules.nix-index ./modules/terminal-kit];
}
```

The `key` makes a repeated import of the kit a no-op. nvf's module has no key
and fails when it is imported twice, so the kit imports it, and consumers must
not import it themselves.

`modules/terminal-kit/default.nix` declares the whole option tree and imports
one file per feature. Each file gates on `enable` and its own switch
(`packages.nix`, `tools.nix`, `yazi.nix`, `git.nix`, `env.nix`, `zsh.nix`,
`bash.nix`, `integration.nix`, `nvf.nix`, `theme.nix`, `clipboard.nix`,
`ai-skills.nix`). Hooks merge into the Home Manager attribute sets, so a
consumer's aliases render next to the kit's, sorted. The flake inputs and
`lib.style` reach the files through `_module.args` as `terminalKitInputs`
and `terminalKitStyle`.

Defaults: everything is on once `enable = true`, except the `dev` package set
(heavy, and its `nodejs` can shadow another Node.js) and agent skills.

## Shell integration *(planned)*

- `owned`: Home Manager's usual rc files.
- `sourced`: the rc files belong to someone else (a workspace image). The kit
  disables Home Manager's `~/.zshenv`, `~/.bash_profile`, `~/.profile` and
  `~/.bash_logout`, sets zsh's `dotDir` under `~/.config/terminal-kit/zsh`
  and moves the generated `.bashrc` to `~/.config/terminal-kit/bash/`. The
  entry files `~/.config/terminal-kit/init.{zsh,bash}` source the Nix
  profile script, the Home Manager session variables and the generated rc
  file, each behind a guard, so a second sourcing adds nothing. They never
  source an image rc file (that would recurse through the one-time
  snippet), never export `ZDOTDIR`, and produce output only when stdout is a
  terminal.
- The one-time snippet is `if [ -r … ]; then . …; fi`: exit status 0 when the
  entry file is missing (no `/nix` mount yet). Activation reads `~/.zshrc`
  and `~/.bashrc` and prints the snippet for a file that lacks it; it never
  writes image files.
- zsh history goes to `zsh.historyPath`, resolved at evaluation time
  (default `<XDG state home>/zsh/history`).

## Theme *(planned, except the CLI tools and the alacritty packages)*

- `lib.style` holds the enfocado light and dark palettes and renderers
  (alacritty TOML, yazi flavors, base16). It depends on `lib` only.
- The CLI tools use the 16 ANSI colours and follow the terminal (available).
- Neovim: vim-enfocado, with `vim.g.enfocado_style = theme.nvf.enfocadoStyle`.
  The mode comes from `theme.modeSource`:
  - `file`: `$XDG_STATE_HOME/my-theme/mode` (`light`/`dark`) decides; a
    `SIGUSR1` makes running instances reread it.
  - `terminal`: without a state file Neovim keeps the background it detects
    from the terminal (OSC 11) and reapplies enfocado when `background`
    changes; with a state file the file wins, also after a late terminal
    reply.
- `nix-terminal-mode light|dark|auto` writes or removes the state file
  (same format as above) and signals Neovim; any other argument exits 64.
- `packages.x86_64-linux.alacritty-theme-enfocado-{light,dark}` render the
  same palettes with `allowedReferences = []` (available), for a terminal on
  a machine without Nix.

## Clipboard *(planned)*

`clipboard = "system"` keeps the X11/Wayland clipboard. `clipboard = "osc52"`
sends Neovim's `+`/`*` yanks and zsh's vi-mode yank to the terminal with
OSC 52 and pastes from the last yank without querying the terminal (most
terminals do not answer a read query, and waiting for one would stall every
paste). No X11/Wayland clipboard tool is installed in that mode.

## The template

`templates/coder` is a complete Home Manager flake. Its inputs follow
`nix-terminal`'s `nixpkgs` and `home-manager`, so a workspace runs the
revisions the checks ran against; it exposes that `home-manager` CLI as
`packages.x86_64-linux.home-manager` for the first switch. `user.nix` holds
the only edits (user name, home directory, state version).

## Checks

`nix flake check --keep-going`; each check fails at build time with a
message naming the offending value, so one run reports every failure.

| Layer | Checks |
| --- | --- |
| Evaluation of two real Home Manager configurations: `Ct` (the template, unedited) and `Co` (every option on, `owned`, user `tester`) | `configs-evaluate`, `packages-sets`, `tools` |
| The template flake, evaluated offline with this flake as `nix-terminal` | `template-evaluates` (it builds exactly `Ct`), `template-exposes-hm-cli` |
| Pure library | `style-palette`, `style-templates`, `style-base16` |
| Build output | `alacritty-theme` (TOML round trip, no store path) |
| Repository scans | `leaks`, `no-os-config`, `formatting` (Alejandra), `ci-workflow-lint` (actionlint) |
| Publication surface | `outputs-shape` (exactly the documented output groups, MIT metadata, LICENSE) |

Generated text is matched with `lib.hasInfix` or line splitting, never with a
wildcard regex (backtracking regexes do not terminate on long inputs).

Planned: runtime shell checks in a fake `$HOME` (silent start, aliases
resolve, nested shells, missing entry file), headless Neovim checks (theme
and clipboard), and a closure check that the template pulls in no GUI
toolkit or clipboard tool.

## Pinning

`flake.lock` pins nixpkgs, home-manager, nvf, nix-index-database and the skill
sources. Consumers that share inputs set `follows`; nix-index-database keeps
its own nixpkgs.
