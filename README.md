# nix-terminal

> **Draft.** The kit is still being built. Everything marked *(planned)* is the
> intended behaviour, not what the module does today.

A Home Manager module with a terminal kit: zsh and bash, git, Neovim (nvf),
CLI tools and the enfocado theme. It is made for machines where Home Manager
must not take over the shell, such as a Coder workspace with its own image
`~/.zshrc`, and it works just as well as an ordinary Home Manager module.

## Outputs

| Output | Content |
| --- | --- |
| `homeModules.default` | the kit, options under `programs.terminalKit` |
| `templates.coder` | a Home Manager flake for a Coder workspace |
| `lib.style` | the enfocado palettes and their renderers (pure, `{lib}` only) |
| `packages.x86_64-linux.alacritty-theme-enfocado-{light,dark}` | alacritty themes without store paths |
| `checks.x86_64-linux.*` | the checks behind `nix flake check` |
| `formatter.x86_64-linux` | Alejandra |

## Quick start: Coder workspace

You need a single-user Nix install and `experimental-features = nix-command
flakes` in `~/.config/nix/nix.conf`.

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

3. Switch with the `home-manager` CLI the template pins (the same revision
   the kit was checked against). The switch also installs that CLI into
   your profile for later runs:

   ```sh
   nix run ~/.config/home-manager#home-manager -- switch --flake ~/.config/home-manager
   ```

   Home Manager refuses to replace a file it did not create; move that file
   away and switch again.

4. Add the one-time snippet to the end of the image's rc files. The entry
   files it sources come with `sourced` mode *(planned)*. It sources
   the kit's entry file only when that file is readable, so a shell started
   before `/nix` is mounted still starts cleanly, and the snippet's exit
   status is 0 either way.

   `~/.zshrc`:

   ```sh
   if [ -r "$HOME/.config/terminal-kit/init.zsh" ]; then . "$HOME/.config/terminal-kit/init.zsh"; fi
   ```

   `~/.bashrc`:

   ```sh
   if [ -r "$HOME/.config/terminal-kit/init.bash" ]; then . "$HOME/.config/terminal-kit/init.bash"; fi
   ```

   *(planned)* Every switch checks both files and prints the snippet for each
   file that lacks it. It never writes to them.

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
  # no git identity: the workspace keeps its own
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

The module imports nvf's and nix-index-database's Home Manager modules itself,
exactly once; do not import them a second time. It reads neither `osConfig`
nor any Stylix option, and it installs every package from your `pkgs`.

## Options

All under `programs.terminalKit`. Everything is on once `enable = true`,
except the `dev` package set and agent skills.

| Option | Default | Status |
| --- | --- | --- |
| `enable` | `false` | available |
| `packages.general.enable` | `true` | available: htop, iotop, lsof, wget, ripgrep, fd, tree, unzip, zip, file, jq |
| `packages.dev.enable` | `false` | available: clang, gnumake, cmake, nodejs, docker-compose, direnv, devenv (see [Claude Code](#claude-code)) |
| `tools.<name>.enable`, name ∈ `bat btop lazygit fzf starship zoxide direnv nixIndex` | `true` | available |
| `yazi.enable` | `true` | *(planned)* yazi with enfocado flavors |
| `git.enable`, `git.{name,email,signingKey,githubUser}`, `git.extraAliases`, `git.includes` | on, identity `null` | *(planned)* with `null` identity values no identity, signing or sign-off is written |
| `zsh.enable`, `zsh.extraAliases`, `zsh.extraInit`, `zsh.historyPath` | on, history `<XDG state home>/zsh/history` | *(planned)* |
| `bash.enable`, `bash.extraAliases` | on | *(planned)* |
| `shellIntegration` | `"owned"` | *(planned)* `owned` or `sourced`, see below |
| `nvf.enable`, `nvf.extraKeymaps` | on | *(planned)* Neovim through nvf, with the Nix LSP `nil` |
| `theme.enable`, `theme.modeSource`, `theme.nvf.enfocadoStyle` | on, `"terminal"`, `"nature"` | *(planned)* see below |
| `clipboard` | `"system"` | *(planned)* `system` or `osc52`, see below |
| `aiSkills.enable`, `aiSkills.skills` | off | *(planned)* see below |

### Shell integration *(planned)*

- `owned`: Home Manager writes `~/.zshrc`, `~/.bashrc` and the other rc files,
  as usual.
- `sourced`: Home Manager writes no file at `~/.zshrc`, `~/.zshenv`,
  `~/.zprofile`, `~/.bashrc`, `~/.profile`, `~/.bash_profile` or
  `~/.bash_logout`. It writes the entry files
  `~/.config/terminal-kit/init.zsh` and `init.bash`, which the one-time
  snippet sources. An entry file never sources an image rc file, does not
  export `ZDOTDIR`, adds nothing twice when sourced twice (nested shells),
  and prints nothing when stdout is not a terminal, so probes such as VS
  Code's `zsh -ilc env` see a silent shell.

### Theme *(planned)*

Neovim uses vim-enfocado in light or dark mode:

- `theme.modeSource = "file"`: the state file `$XDG_STATE_HOME/my-theme/mode`
  (`light` or `dark`) decides.
- `theme.modeSource = "terminal"`: the terminal's background decides, unless
  the state file exists. The command `nix-terminal-mode light|dark|auto`
  writes or removes the state file and tells running Neovim instances;
  `auto` returns to the terminal's background. Any other argument exits 64
  with a usage message.

The CLI tools use the terminal's 16 ANSI colours, so they follow the terminal
palette (available).

### Clipboard *(planned)*

- `clipboard = "system"`: Neovim and zsh use the X11/Wayland clipboard.
- `clipboard = "osc52"`: for a terminal on another machine. Neovim's `+` and
  `*` registers and zsh's vi-mode yank are sent to the terminal clipboard
  with OSC 52. It is copy-only: a paste comes from the last yank and never
  asks the terminal, so `p` never waits. No X11/Wayland clipboard tool is
  installed.

### Agent skills *(planned)*

`aiSkills.enable = true` links a curated set of agent skills into
`~/.agents/skills/<name>` and `~/.claude/skills/<name>`; `aiSkills.skills`
adds your own. Nothing else under `~/.claude` is touched.

## Claude Code

The template leaves a pre-installed Claude Code alone: it installs no
`claude` package, defines no `claude` alias or function, sets no
`ANTHROPIC_*`, `CLAUDE_*` or `AWS_*` variable, creates nothing under
`~/.claude` except skill links, and keeps the `dev` package set off.

The `dev` package set contains `nodejs`. Once the kit's profile is on `PATH`
in front of the image's directories, that `node` can shadow the Node.js a
pre-installed Claude Code runs on. Check before you enable it:

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

and copy it from Windows `cmd`, with `ws` your ssh host for the workspace:

```bat
scp ws:enfocado-dark/enfocado-dark.toml "%APPDATA%\alacritty\enfocado-dark.toml"
```

Then import it in `%APPDATA%\alacritty\alacritty.toml`:

```toml
[general]
import = ["enfocado-dark.toml"]
```

Use `alacritty-theme-enfocado-light` and `enfocado-light.toml` for the light
variant. Switching between them on Windows is manual.

## Checks

```sh
nix flake check --keep-going
```

The checks evaluate two configurations with the real Home Manager: the
template, unedited, and an "owned" test configuration with every option on.
They also scan the repository for personal data (e-mail addresses, key ids,
home paths), check the palettes and theme packages, the template flake, the
output groups, the formatting (Alejandra) and the CI workflow (actionlint).
CI runs the same command on every push (`.github/workflows/check.yml`).

Design notes: [docs/architecture.md](docs/architecture.md).

## Credits and licence

MIT, see [LICENSE](LICENSE).

- The enfocado palette comes from
  [vim-enfocado](https://github.com/wuelnerdotexe/vim-enfocado) (MIT).
- Portions are adapted from
  [Home Manager](https://github.com/nix-community/home-manager) (MIT); files
  that contain them say so.
