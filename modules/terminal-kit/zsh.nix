# zsh.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.terminalKit;
  # External commands the start-up runs, by store path: the image may lack
  # them (ncurses is not in the kit's profile).
  tput = lib.getExe' pkgs.ncurses "tput";
  grep = lib.getExe' pkgs.gnugrep "grep";
  # clipboard = "osc52" (R15, Snippet 10): the vi yank widgets also send
  # the cut buffer to the terminal clipboard. The target is overridable
  # for tests (PD8).
  osc52Widget = ''
    _tk_osc52() { printf '\e]52;c;%s\a' "$(printf '%s' "$1" | ${pkgs.coreutils}/bin/base64 | ${pkgs.coreutils}/bin/tr -d '\n')" > "''${TERMINAL_KIT_OSC52_TTY:-/dev/tty}"; }
    for w in vi-yank vi-yank-eol vi-yank-whole-line; do
      eval "_tk-$w() { zle .$w; _tk_osc52 \"\$CUTBUFFER\" }"
      zle -N $w _tk-$w
    done
  '';
in {
  config = lib.mkIf (cfg.enable && cfg.zsh.enable) {
    programs.zsh = {
      enable = true;

      # Features
      enableCompletion = true;
      # enableLsColors = true;
      syntaxHighlighting.enable = true;
      autosuggestion.enable = true;
      defaultKeymap = "viins"; # vi mode

      history = rec {
        size = 2147483647;
        save = size;
        extended = true; # save timestamps
        path = cfg.zsh.historyPath;
      };

      # Aliases
      shellGlobalAliases = {
        H = "| head";
        L = "| less";
      };
      shellAliases =
        {
          # General
          rm = "rm -I";

          cdd = "cd ~/downloads";
          cdp = "cd ~/projects";
          cdff = "/tmp/ffdownloads";
          cdnpc = "cd ~/.config/nixpkgs";

          ls = "ls --group-directories-first --color=always --escape --human-readable --classify";
          l = "ls -l";
          la = "ls -lah";
          lh = "ls -hAl";
          ll = "ls -l";
          lt = "ls -lt";

          dd = "sudo dd status=progress bs=4M conv=fsync";
          df = "df -h";

          cp = "cp -i";
          cpf = "\cp -f";

          mv = "mv -i";
          mp = "mkdir -p";
          mdcd = "mkdir -cd";
          md = "mkdir $(date -I)";
          mcp = "noglob zmv -C -W";
          mln = "noglob zmv -L -W";
          mmv = "noglob zmv -W";

          # File Tools
          t = "tree -C";
          ta = "tree -a";
          f = "find";
          ff = "find . -type f -iname ";
          fd = "find . -type d -iname ";

          blk = "lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,FSSIZE,FSAVAIL,FSUSE%,MOUNTPOINT,RO,RM";
          lsblk = "blk";
          dsize = "sudo du -hsx ./* | sort -rh | head -n 40";

          # Nix
          nq = "nix-env -q";
          ne = "nix-env -e";
          nh = "nix-hash --type sha256 --flat --base32";
          nd = ''nix develop --command "zsh"'';
          ndi = ''nix develop --impure --command "zsh"'';
          ns = ''nix-shell --pure --command "zsh"'';
          nsi = ''nix-shell --impure --command "zsh"'';
          nqp = ''nix-store --query --references $(nix-instantiate "<nixpkgs>" -A dev-packages)'';

          serve = "miniserve -g -z -p 12345";

          # SSH
          ssh = "TERM=xterm-256color ssh";
          ssh-tmate = "ssh -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no";

          rcp = "rsync --filter=':- .gitignore' --exclude '.git' --append-verify --archive --compress --human-readable --info=progress2 --partial --sparse";
          tailswitch = ''tailscale switch $(tailscale switch --list | fzf | cut -d ' ' -f1) && sudo tailscale up --operator=$USER'';

          # vim configs
          v = "(file=$('fd' --type f | fzf --height 80% --reverse) && nvim \"$file\")";
          vim = "nvim";
          vn = "nvim /etc/nixos/configuration.nix";
          vnpc = "nvim ~/.config/nixpkgs/config.nix";
          vssh = "nvim ~/.ssh/config";
          vza = "nvim ~/.zaliases";

          # Dev
          g = "git";
          m = "make";
          mc = "make clean";
          k = "kubectl";
          c = "cargo";
          scala = "scala -Dscala.color -deprecation -unchecked -explaintypes -language:_";
          amm = "amm --no-remote-logging";
          jsb = "underscore print --color --outfmt json"; # beautify json, package: npm -g install underscore-cli

          # Docker
          dr = "docker";
          drc = "docker container";
          dri = "docker image";
          drv = "docker volume";
          drn = "docker network";
          drcl = "docker container ls";
          dril = "docker image ls";
          drvl = "docker volume ls";
          drnl = "docker network ls";
          drcr = "docker container rm";
          drvr = "docker volume rm";
          drir = "docker image rm";
          drnr = "docker network rm";
          drstop = "docker stop";
          drstart = "docker start";
          drps = "docker ps --format 'table {{ .Names }}\t{{ .Status }}\t{{ .Ports }}\t{{ .Networks }}'";
          drpsl = "docker ps";
          drl = "docker logs";
          drst = "docker status";
          drex = "docker exec -it";
          dcup = "docker compose up -d";
          dcdown = "docker compose down";
          drsys = "docker system df -v";

          # Internet and Wlan
          has_dns = ''dig +short @1.1.1.1 ccc.de | grep -q "." && echo "dns online" || echo "dns offline"'';
          has_inet = "ping -q -w 1 -c 1 1.1.1.1 > /dev/null && echo online || echo offline";
          won = "nmcli radio wifi on; wscan";
          woff = "nmcli radio wifi off";
          wscan = "nmcli dev wifi rescan > /dev/null 2>&1; true";
          wlist = "nmcli dev wifi list";
          wcon = "nmcli dev wifi connect";

          nload = "nload -u h";
        }
        // cfg.zsh.extraAliases;
      dotDir = "${config.xdg.configHome}/zsh";

      setOptions = [
        "NONOMATCH" # avoid the zsh "no matches found" / allows typing sbt ~compile
        "INTERACTIVECOMMENTS" # allow comments in interactive shell
        "HASH_LIST_ALL" # rehash command path and completions on completion attempt
        "BANG_HIST" # Treat the '!' character specially during expansion.
        "INC_APPEND_HISTORY" # Write to the history file immediately, not when the shell exits.
        "SHARE_HISTORY" # Share history between all sessions
        "HIST_EXPIRE_DUPS_FIRST" # Expire duplicate entries first when trimming history.
        "HIST_IGNORE_DUPS" # Don't record an entry that was just recorded again.
        "HIST_FIND_NO_DUPS" # Do not display a line previously found.
        "HIST_IGNORE_SPACE" # Don't record an entry starting with a space.
        "HIST_REDUCE_BLANKS" # Remove superfluous blanks before recording entry.
        "HIST_VERIFY" # Don't execute immediately upon history expansion.
      ];

      initContent =
        ''
          # workaround for rust-analyzer not finding CC in nix shell
          # export CC="gcc";

          # history prefix search
          autoload -U history-search-end # have the cursor placed at the end of the line once you have selected your desired command
          bindkey '^[[A' history-beginning-search-backward
          bindkey '^[[B' history-beginning-search-forward

          # zsh with pwd in window title
          function precmd {
              [[ -t 1 ]] || return
              echo -en "\007" # after every command, set the window to urgent, by ringing the bell
              term=$(echo $TERM | ${grep} -Eo '^[^-]+')
              print -Pn "\e]0;$term - zsh %~\a"
          }

          # current command with args in window title
          function preexec {
              [[ -t 1 ]] || return
              term=$(echo $TERM | grep -Eo '^[^-]+')
              printf "\033]0;%s - %s\a" "$term" "$1"
          }

          # edit command line in nvim
          autoload -z edit-command-line
          zle -N edit-command-line
          bindkey -M vicmd "^v" edit-command-line
          bindkey -M viins "^v" edit-command-line

          # Cursor shape per vi keymap (DECSCUSR `CSI Ps SP q`): 1 = block in
          # command mode, 5 = beam in insert mode, for every new line, at
          # start-up and when a command starts.
          if [[ -t 1 ]]; then
            zle-keymap-select() {
              case $KEYMAP in
                vicmd) printf '\e[1 q' ;;
                viins | main) printf '\e[5 q' ;;
              esac
            }
            zle-line-init() {
              zle -K viins
              printf '\e[5 q'
            }
            zle -N zle-keymap-select
            zle -N zle-line-init
            printf '\e[5 q'
            # This preexec replaces the title preexec above, as it always has.
            preexec() { printf '\e[5 q'; }
          fi

          # map HOME/END in vi mode
          # https://github.com/jeffreytse/zsh-vi-mode/issues/59#issuecomment-862729015
          # https://github.com/jeffreytse/zsh-vi-mode/issues/134
          bindkey -M viins "^[[H" beginning-of-line
          bindkey -M viins  "^[[F" end-of-line
          bindkey -M vicmd "^[[H" beginning-of-line
          bindkey -M vicmd "^[[F" end-of-line
          bindkey -M visual "^[[H" beginning-of-line
          bindkey -M visual "^[[F" end-of-line

          # in zshrc: 10ms timeout waiting for keysequences
          export KEYTIMEOUT=1

          export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
          export FZF_DEFAULT_OPTS="--extended --multi --ansi" # extended match and multiple selections
          export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

          # colorize manpages
          if [[ -t 1 ]]; then
            export LESS_TERMCAP_mb="$(${tput} bold; ${tput} setaf 6)";
            export LESS_TERMCAP_md="$(${tput} bold; ${tput} setaf 2)";
            export LESS_TERMCAP_me="$(${tput} sgr0)";
            export LESS_TERMCAP_so="$(${tput} bold; ${tput} setaf 0; ${tput} setab 6)";
            export LESS_TERMCAP_se="$(${tput} rmso; ${tput} sgr0)";
            export LESS_TERMCAP_us="$(${tput} smul; ${tput} bold; ${tput} setaf 3)";
            export LESS_TERMCAP_ue="$(${tput} rmul; ${tput} sgr0)";
            export LESS_TERMCAP_mr="$(${tput} rev)";
            export LESS_TERMCAP_mh="$(${tput} dim)";
            export LESS_TERMCAP_ZN="$(${tput} ssubm)";
            export LESS_TERMCAP_ZV="$(${tput} rsubm)";
            export LESS_TERMCAP_ZO="$(${tput} ssupm)";
            export LESS_TERMCAP_ZW="$(${tput} rsupm)";
          fi
          export GROFF_NO_SGR=1;

          cdg() {
              # Traverse upwards until you find a .git directory
              local dir=$(git rev-parse --show-toplevel 2>/dev/null)
              if [ -n "$dir" ]; then
                  cd "$dir" || echo "Failed to change directory."
              else
                  echo "Not a git repository."
              fi
          }
          cdl() { cd "$1"; ls; }

          # Reverse search links
          rln() {
              # $1 file, $2 searchpath
              searchpath="$2"
              find -L "${searchpath:-}" -samefile $1
          }

          p() { cd "~/projects/$(ls -t ~/projects | fzf --query="$(echo $@ | tr ' ' '\ ' )")";}
          vb() { nvim $(which $1); }

          mmmv() {
              mmv -n $1 $2 | cut -f4 -d ' ' | xargs mkdir -p
              mmv "$1/*" "$2/*"
          }

          # FZF
          fif() {
              RG_PREFIX="rg --column --smart-case --no-heading --files-with-matches --hidden"
              fzf --bind "change:reload:$RG_PREFIX {q} || true" --ansi --disabled --preview 'rg --color=always --smart-case -C 5 {q} {+}' --preview-window wrap $@
          }
          fiv() {
              # RG_PREFIX="rg --column --smart-case --line-number --no-heading"
              RG_PREFIX="rg --column --smart-case --no-heading --files-with-matches --hidden"
              file="$(fzf --bind "change:reload:$RG_PREFIX {q} || true" --ansi --disabled --preview 'rg --color=always --smart-case -C 5 {q} {+}' --preview-window wrap $@)"
              nvim "$file"
          }
          fivl() {
              local query="" file="" output exit_code
              local RG_PREFIX="rg --column --smart-case --no-heading --files-with-matches --hidden"

              while true; do
                  output=$(fzf --bind "change:reload:$RG_PREFIX {q} || true" \
                              --ansi \
                              --disabled \
                              --preview 'rg --color=always --smart-case -C 5 {q} {+}' \
                              --preview-window wrap \
                              --print-query \
                              -q "$query")
                  exit_code=$?

                  query="''${output%%$'\n'*}"

                  if [[ $exit_code -ne 0 ]]; then
                      break
                  fi

                  # Escaped here as well
                  file="''${output#*$'\n'}"

                  if [[ -z "$file" ]]; then
                      break
                  fi

                  # Escaped EDITOR fallback
                  nvim "$file" || break
              done
          }

          # Docker
          dricl() { docker image rm -f $(docker images -q) }
          drsa() { docker stop $(docker ps -a -q) }
          drsh() { docker exec -it $1 sh }
          drbash() { docker exec -it $1 bash }
          drls() {
              echo "Containers"
              docker container ls
              echo -e "\nVolumes"
              docker volume ls
              echo -e "\nNetworks"
              docker network ls
              echo -e "\nImages"
              docker image ls
          }
          drclean1() {
              docker stop $(docker ps -a -f name="$1" -q )
              docker container rm -f $(docker ps -a -f name="$1" -q )
              docker network rm $(docker network ls -f name="$1" -q )
          }
          drclean1f() {
              docker stop $(docker ps -a -f name="$1" -q )
              docker container rm -f $(docker ps -a -f name="$1" -q )
              docker network rm $(docker network ls -f name="$1" -q )
              docker image rm -f $(docker images ls -f -q | grep -i "$1" )
          }
          drclean1ff() {
              docker stop $(docker ps -a -f name="$1" -q )
              docker container rm -f $(docker ps -a -f name="$1" -q )
              docker network rm $(docker network ls -f name="$1" -q )
              docker volume rm -f $(docker volume ls -f name="$1" -q )
          }
          drclean() {
              docker stop $(docker ps -a -q )
              docker container rm -f $(docker ps -a -q )
              docker network rm $(docker network ls -q )
          }
          drcleanf() {
              docker stop $(docker ps -a -q )
              docker container rm -f $(docker ps -a -q )
              docker network rm $(docker network ls -q )
              docker image rm -f $(docker images -q )
          }
          drcleanff() {
              docker stop $(docker ps -a -q )
              docker container rm -f $(docker ps -a -q )
              docker network rm $(docker network ls -q )
              docker image rm -f $(docker images -q )
              docker volume rm -f $(docker volume ls -q )
          }
          drclean?() {
              local numContainer="$(docker container ls -q | wc -l)"
              local numVolumes="$(docker volume ls -q | wc -l)"
              local numNetworks="$(docker network ls -q | wc -l)"
              if [[ "$numContainer" -eq 0 && "$numVolumes" -eq 0 && "$numNetworks" -eq 3 ]]; then
                  echo "Docker clean"
              else
                  echo "Docker unclean"
              fi
          }

          sshkeygen() {
              ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)->$1 on $(date -I)" -f "$HOME/.ssh/$(hostname)->$1"
          }
          sshkeygen_legacy() {
              ssh-keygen -t rsa -b 4096 -C "$(whoami)@$(hostname)->$1 on $(date -I)" -f "$HOME/.ssh/$(hostname)->$1_legacy"
          }

          tmpremount() {
              sudo mount -o remount,size="$1",noatime /tmp
          }

          nixos-details() {
              printf '- System: '
              nixos-version
              printf '- Nix version: '
              nix-env --version
              printf '- Nixpkgs version: '
              nix-instantiate --eval '<nixpkgs>' -A lib.nixpkgsVersion
              printf '- Sandboxing enabled: '
              grep build-use-sandbox /etc/nix/nix.conf | sed s/.*=//
          }

          search_replace() {
              ag "$1" -l0 | xargs -0 sed -i "s/$1/$2/g"
          }
          search_replace_all() {
              ag -a --hidden "$1" -l0 | xargs -0 sed -i "s/$1/$2/g"
          }

          # wrap the ollama command, if the parameter is pull with no other parameters pull all models
          function ollama_update() {
              echo "pulling all models..."
              ollama list | awk '$1 !~ /^registry.local/ {print $1}' | while read -r model; do
                echo "Pulling $model"
                ollama pull "$model"
              done
          }
        ''
        + lib.optionalString (cfg.clipboard == "osc52") ("\n" + osc52Widget)
        + lib.optionalString (cfg.zsh.extraInit != "") ("\n" + cfg.zsh.extraInit);

      # zsh-system-clipboard talks to the X11/Wayland clipboard: only with
      # clipboard = "system" (R15).
      plugins =
        lib.optional (cfg.clipboard == "system") {
          name = "zsh-system-clipboard";
          src = pkgs.zsh-system-clipboard;
          file = "share/zsh/zsh-system-clipboard/zsh-system-clipboard.zsh";
        }
        ++ [
          {
            name = "zsh-print-alias";
            file = "print-alias.plugin.zsh";
            src = pkgs.fetchFromGitHub {
              owner = "brymck";
              repo = "print-alias";
              rev = "8997efc356c829f21db271424fbc8986a7203119";
              sha256 = "sha256-6ZyRkg4eXh1JVtYRHTfxJ8ctdOLw4Ff8NsEqfpoxyfI=";
            };
          }
          {
            name = "mill-zsh-completions";
            file = "mill-zsh-completions.plugin.zsh";
            src = pkgs.fetchFromGitHub {
              owner = "carlosedp";
              repo = "/mill-zsh-completions";
              rev = "3e66e19868bda2f361d6ea8cb8abb8ff91dcc920";
              sha256 = "sha256-zmWTT65HlVsvFTGzs5SQsVqSHc1XaLwCHmiWZgkZsCU=";
            };
          }
        ];
    };
  };
}
