# nix-terminal

A Home Manager module with a terminal kit: zsh and bash, git and tig, Neovim
(nvf), yazi, CLI tools and the enfocado theme. It is made for machines where
Home Manager must not take over the shell, such as a Coder workspace whose
image owns `~/.zshrc`, and it works just as well as an ordinary Home Manager
module.

## Outputs

| Output | Content |
| --- | --- |
| `homeModules.default` | the kit, options under `programs.terminalKit` |
| `templates.coder` | a Home Manager flake for a Coder workspace |
| `lib.style` | the enfocado palettes and their renderers (pure, `{lib}` only) |
| `packages.x86_64-linux.alacritty-theme-enfocado-{light,dark}` | alacritty themes without store paths |
| `checks.x86_64-linux.*` | the checks behind `nix flake check` |
| `formatter.x86_64-linux` | Alejandra |

## Checking a workspace before setup

`scripts/workspace-probe.sh` is a self-contained bash script that measures
what the kit assumes about a workspace: that Nix substitutes from
cache.nixos.org, that interactive shells reach the end of `~/.zshrc` and
`~/.bashrc`, the shell start time, whether the terminal answers OSC 11 and
DA1 and passes OSC 52 to the Windows clipboard, and how `pgrep` sees Neovim.
It needs only bash 4 and the usual coreutils, procps and util-linux.

```sh
curl -fsSLo ~/workspace-probe.sh https://raw.githubusercontent.com/GRBurst/nix-terminal/main/scripts/workspace-probe.sh
bash ~/workspace-probe.sh baseline [private-repo-url]
bash ~/workspace-probe.sh terminal --label vscode   # once per terminal: vscode, alacritty-ssh, cmd
# after the setup:
bash ~/workspace-probe.sh compare ~/.cache/terminal-kit-probe/baseline-nolabel-<timestamp>.txt [private-repo-url]
```

`baseline` appends one line to `~/.zshrc` and `~/.bashrc` while it starts
the shells, and restores both from a backup (it checks the sha256
afterwards). It changes nothing else. `terminal` asks you to paste into
Notepad and answer y or n. `compare` hashes the files again and shows a
diff for each changed rc file. After the setup, only the two rc files should differ,
by the snippet you appended. Every report is printed and also saved under
`~/.cache/terminal-kit-probe/`. Reports contain no environment values,
URLs, host names or home paths: the repository URL shows up only as a hash.

Every finding is rated OK, INFO, HEADS-UP or BLOCKER. A summary, printed
last and placed first in the saved report, lists each heads-up and blocker
with why it matters and what to do. All three commands exit 0 without a
BLOCKER, 1 with one, 2 on a usage error and 3 if an rc file could not be
restored. `baseline` keeps private copies of the rc files (mode 600, never
in a report), so `compare` can print their diff and accept exactly one
added snippet line as expected.

## Quick start: Coder workspace

On the workspace you need a single-user Nix install and
`experimental-features = nix-command flakes` in `~/.config/nix/nix.conf`.

1. Create the configuration from the template:

   ```sh
   mkdir -p ~/.config/home-manager && cd ~/.config/home-manager
   nix flake init -t github:GRBurst/nix-terminal#coder
   ```

2. Edit `user.nix` only if a default does not fit. These are the only edits
   the template needs:

   | Field | Default | Becomes |
   | --- | --- | --- |
   | `name` | `coder` | `home.username` and the `homeConfigurations` name |
   | `homeDirectory` | `/home/coder` | `home.homeDirectory` |
   | `stateVersion` | `26.05` | `home.stateVersion` |

3. Switch with the `home-manager` CLI the template pins (the revision the
   kit's checks ran against). The switch also installs that CLI, so later
   runs are `home-manager switch --flake ~/.config/home-manager`:

   ```sh
   nix run ~/.config/home-manager#home-manager -- switch --flake ~/.config/home-manager
   ```

   Home Manager refuses to replace a file it did not create; move that file
   away (or add `-b backup`) and switch again.

4. Append the one-time snippet to the image's rc files. It sources the kit's
   entry file only when that file is readable, so a shell started before
   `/nix` is mounted still starts, and its exit status is 0 either way.

   `~/.zshrc`:

   ```sh
   if [ -r "$HOME/.config/terminal-kit/init.zsh" ]; then . "$HOME/.config/terminal-kit/init.zsh"; fi
   ```

   `~/.bashrc`:

   ```sh
   if [ -r "$HOME/.config/terminal-kit/init.bash" ]; then . "$HOME/.config/terminal-kit/init.bash"; fi
   ```

   Every switch checks both files and prints this line for each file that
   does not mention its entry path; it never writes to them. Run
   `terminal-kit-check-snippet` for the same check by hand.

What the template sets (`home.nix`):

```nix
programs.home-manager.enable = true;
programs.terminalKit = {
  enable = true;
  shellIntegration = "sourced";
  clipboard = "osc52";
  theme.modeSource = "terminal";
  aiSkills.enable = true;
  packages.dev.enable = false;
  # No git identity: the workspace keeps its own.
};
```

## Using the module in your own flake

```nix
{
  inputs.nix-terminal.url = "github:GRBurst/nix-terminal";
  # To share your nixpkgs/home-manager, add `follows` for them.

  outputs = {nix-terminal, ...}: {
    # in a homeManagerConfiguration, or in home-manager.sharedModules:
    #   modules = [nix-terminal.homeModules.default {programs.terminalKit.enable = true;}];
  };
}
```

The module imports nvf's and nix-index-database's Home Manager modules
itself; do not import them a second time. It reads neither `osConfig` nor
any Stylix option, and it installs every package from your `pkgs`.

## Options

All under `programs.terminalKit`. Everything is on once `enable = true`,
except the `dev` package set and agent skills. The check `readme-options`
keeps this table and the option tree in step.

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `false` | the kit |
| `shellIntegration` | `"owned"` | `"owned"` or `"sourced"`, see [Shell integration](#shell-integration) |
| `clipboard` | `"system"` | `"system"` or `"osc52"`, see [Clipboard](#clipboard) |
| `packages.general.enable` | `true` | htop, iotop, lsof, wget, ripgrep, fd, tree, unzip, zip, file, jq |
| `packages.dev.enable` | `false` | clang, gnumake, cmake, nodejs, docker-compose, direnv, devenv (see [Claude Code](#claude-code)) |
| `tools.bat.enable`, `tools.btop.enable`, `tools.lazygit.enable`, `tools.fzf.enable`, `tools.starship.enable`, `tools.zoxide.enable`, `tools.direnv.enable`, `tools.nixIndex.enable` | `true` | one switch per tool; direnv with nix-direnv, nix-index with nix-index-database |
| `yazi.enable` | `true` | yazi (shell wrapper `yy`) with the enfocado flavors |
| `yazi.flavorOverrides` | `{}` | TOML merged into the flavors: `shared`, `light`, `dark` |
| `git.enable` | `true` | git with the kit's settings and aliases, and tig |
| `git.name`, `git.email` | `null` | `user.name`, `user.email`; with both set, commits get a sign-off |
| `git.signingKey` | `null` | OpenPGP key id; set, commits and tags are signed |
| `git.githubUser` | `null` | GitHub user of the `clus` alias; `null` omits it |
| `git.extraAliases` | `{}` | merged into the git aliases |
| `git.includes` | `[]` | passed to `programs.git.includes` |
| `git.tigExtraConfig` | `""` | appended to the kit's `tig/config` |
| `zsh.enable` | `true` | zsh in vi mode, with the kit's aliases and plugins |
| `zsh.extraAliases` | `{}` | merged into the zsh aliases |
| `zsh.extraInit` | `""` | appended to the zsh init, after the kit's own |
| `zsh.historyPath` | `<XDG state home>/zsh/history` | the history file |
| `bash.enable` | `true` | bash |
| `bash.extraAliases` | `{}` | the bash aliases |
| `nvf.enable` | `true` | Neovim through nvf, with the Nix language server `nil` |
| `nvf.extraKeymaps` | `[]` | appended after the kit's keymaps |
| `theme.enable` | `true` | vim-enfocado in Neovim, enfocado flavors in yazi |
| `theme.modeSource` | `"terminal"` | `"terminal"` or `"file"`, see [Theme](#theme) |
| `theme.nvf.enfocadoStyle` | `"nature"` | `vim.g.enfocado_style` |
| `aiSkills.enable` | `false` | links the curated agent skills, see [Agent skills](#agent-skills) |
| `aiSkills.skills` | `{}` | your own skills, merged with the curated set |

### Shell integration

- `owned`: Home Manager writes the rc files as usual: `~/.zshenv` (which
  points zsh at `~/.config/zsh`), `~/.bashrc`, `~/.profile` and
  `~/.bash_profile`.
- `sourced`: Home Manager writes nothing at `~/.zshrc`, `~/.zshenv`,
  `~/.zprofile`, `~/.bashrc`, `~/.profile`, `~/.bash_profile` or
  `~/.bash_logout`. It writes the entry files
  `~/.config/terminal-kit/init.zsh` and `init.bash`, which the one-time
  snippet sources. An entry file never sources an image rc file, does not
  export `ZDOTDIR`, adds nothing to `PATH` twice in nested shells, and
  prints nothing when stdout is not a terminal, so probes such as VS Code's
  `zsh -ilc env` see a silent shell.

### Theme

The CLI tools use the terminal's 16 ANSI colours and follow its palette.
Neovim uses vim-enfocado in light or dark mode:

- `theme.modeSource = "terminal"`: the terminal's background decides,
  unless the state file `$XDG_STATE_HOME/my-theme/mode` (`light` or `dark`)
  exists. `nix-terminal-mode light` or `dark` writes the state file and
  switches running Neovim instances; `nix-terminal-mode auto` removes it, so
  Neovim started afterwards follows the terminal again (running instances
  keep their mode). Any other argument exits 64 with a usage message.
- `theme.modeSource = "file"`: the state file decides (`light` when it is
  missing); something else, such as darkman, writes it and sends Neovim
  `SIGUSR1`. `nix-terminal-mode` is not installed.

### Clipboard

- `clipboard = "system"`: Neovim and zsh use the X11/Wayland clipboard.
- `clipboard = "osc52"`: for a terminal on another machine. Neovim's yanks
  (the `+` and `*` registers, which plain `y` uses) and zsh's vi-mode yanks
  are sent to the terminal's clipboard with OSC 52. It is copy-only: a
  paste inside Neovim returns the last yank and never asks the terminal, so
  `p` never waits; paste from Windows with the terminal's own paste key. No
  X11/Wayland clipboard tool is installed. Alacritty accepts OSC 52 copies
  by default.

### Agent skills

`aiSkills.enable = true` links a curated set (14 skills from
[obra/superpowers](https://github.com/obra/superpowers), `xp-clean-code`
and `karpathy-guidelines`) into `~/.agents/skills/<name>` and
`~/.claude/skills/<name>`; `aiSkills.skills` adds your own (the attribute
name must equal the skill's `name`). Nothing else under `~/.claude` is
touched.

## Claude Code

The template leaves a pre-installed Claude Code alone: it installs no
`claude` package, defines no `claude` alias or function, sets no
`ANTHROPIC_*`, `CLAUDE_*` or `AWS_*` variable, creates nothing under
`~/.claude` except skill links, and keeps the `dev` package set off.

The `dev` package set contains `nodejs`. The kit's profile comes first on
`PATH`, so its `node` can shadow the Node.js a pre-installed Claude Code runs
on. Check before you enable it:

```sh
head -n 1 "$(command -v claude)"   # '#!/usr/bin/env node' means: the first node on PATH
type -a node                       # which node comes first today
node --version
```

Enable `packages.dev.enable`, switch, open a new shell and repeat the check.
If a Nix `node` (under `~/.nix-profile` or `/nix/store`) now comes first and
`claude` starts with `#!/usr/bin/env node`, Claude Code runs on that Node.js.
Keep `dev` off, or make sure that version works for it. Programs installed
from Nix, including with `nix profile install`, refer to their own Node.js
by store path and are not affected.

## Windows alacritty theme

The theme packages contain one TOML file each and no store path, so the file
works on a machine without Nix. Build it on the workspace:

```sh
nix build github:GRBurst/nix-terminal#alacritty-theme-enfocado-dark --out-link ~/enfocado-dark
```

and copy it from Windows `cmd`, with `ws` the workspace's ssh host (for
example `coder.<workspace>` after `coder config-ssh`):

```bat
if not exist "%APPDATA%\alacritty" mkdir "%APPDATA%\alacritty"
scp ws:enfocado-dark/enfocado-dark.toml "%APPDATA%\alacritty\enfocado-dark.toml"
```

Then import it in `%APPDATA%\alacritty\alacritty.toml` (create the file if
it does not exist; `[general]` and imports relative to this file need
alacritty 0.14 or later):

```toml
[general]
import = ["enfocado-dark.toml"]
```

Use `alacritty-theme-enfocado-light` and `enfocado-light.toml` for the light
variant. Switching between them on Windows is manual; with
`theme.modeSource = "terminal"` Neovim on the workspace follows.

## Checks

```sh
nix flake check --keep-going
```

The checks evaluate two configurations with the real Home Manager: the
template, unedited, and an `owned` configuration with every option on. They
run the sourced shells in a scratch `$HOME` (silent start, nested shells,
missing entry file, the snippet check), the workspace probe (shellcheck and
a run of `baseline` in a scratch `$HOME`), headless Neovim (theme, mode
signal, OSC 52 clipboard) and `nix-terminal-mode`; they check the template's
closure for GUI toolkits and clipboard tools, the Claude Code guarantees
above, the palettes and theme packages, the template flake, the output
groups, this README's option table, the formatting (Alejandra) and the CI
workflow (actionlint), and they scan the repository for personal data
(e-mail addresses, key ids, home paths). CI runs the same command on every
push (`.github/workflows/check.yml`).

Design notes: [docs/architecture.md](docs/architecture.md).

## Credits and licence

MIT, see [LICENSE](LICENSE).

- The enfocado palette and the Neovim colour scheme come from
  [vim-enfocado](https://github.com/wuelnerdotexe/vim-enfocado) (MIT).
- Portions are adapted from
  [Home Manager](https://github.com/nix-community/home-manager) (MIT); the
  files that contain them say so.
