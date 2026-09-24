# zsh.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.terminalKit;
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
