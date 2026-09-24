# git and tig.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.terminalKit.git;
  signing = cfg.signingKey != null;
  # Identity-dependent content is written only with the values it needs (D22).
  named = cfg.name != null;
  identified = cfg.name != null && cfg.email != null;

  # A branch-relative alias body: `f` is a shell function so the alias can take
  # arguments. `$(git config init.defaultBranch)` keeps them working in repos
  # whose default branch is not `main`.
  defaultBranch = "$(git config init.defaultBranch)";
  resignExec = "git rebase --exec 'git commit --amend --no-edit -n -S --author=\"$(git config user.name) <$(git config user.email)>\"'";
  latestFormat = "%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(color:red)%(objectname:short)%(color:reset) - %(contents:subject) - %(authorname) (%(color:green)%(committerdate:relative)%(color:reset))";
in {
  config = lib.mkIf (config.programs.terminalKit.enable && cfg.enable) (lib.mkMerge [
    {
      # Only tig itself is installed here.
      home.packages = [pkgs.tig];

      xdg.configFile."tig/config".text = builtins.readFile ./git/tig/config + cfg.tigExtraConfig;

      programs.git = {
        enable = true;

        inherit (cfg) includes;

        settings = {
          alias =
            {
              # Most used
              a = "add";
              A = "add -A";
              cl = "clone";
              st = "status";
              h = "help";

              clu = "!f() { git clone $1 && git remote add upstream $2 && git remote -v ; }; f";
            }
            // lib.optionalAttrs (cfg.githubUser != null) {
              clus = "!f() { IN=(\${1//// }); git clone git@github.com:${cfg.githubUser}/\${IN[1]} && cd \${IN[1]} && git remote add upstream git@github.com:$1 && git remote -v ; }; f";
            }
            // {
              # What did HEAD change since it diverged from the default branch (...),
              # and how is HEAD different to it (..)?
              review = "!f() { git diff -p ${defaultBranch}...HEAD; }; f";
              review2 = "!f() { git diff -p ${defaultBranch}..HEAD; }; f";
              review-files = "!f() { git diff --name-only ${defaultBranch}...HEAD; }; f";
              review-files2 = "!f() { git diff --name-only ${defaultBranch}..HEAD; }; f";

              # Branch
              b = "branch";
              br = "branch -r";
              bd = "branch -d";
              bD = "branch -D";
              bdr = "push origin --delete";
              brename = "branch -m";
              btw = "!f() { git checkout $(git remote show origin | sed -n '/HEAD branch/s/.*: //p'); }; f";

              # Checkout
              o = "checkout";
              ob = "checkout -b";
              obm = "!f() { git checkout -b $1 ${defaultBranch}; }; f";
              om = "!f() { git checkout ${defaultBranch}; }; f";
              oom = "!f() { git checkout origin/${defaultBranch}; }; f";
              ot = "!f() { local tmpCommit=\${1:-master} && echo $tmpCommit && mkdir -p /tmp/wust && git --work-tree=/tmp/wust checkout $tmpCommit -- . ; }; f";

              # Worktree
              w = "worktree";
              wa = "worktree add";
              wr = "worktree remove";
              wd = "worktree remove";
              wl = "worktree list";

              # Fetch
              f = "fetch";
              fu = "fetch upstream";
              # Fetch upstream and merge the default branch.
              fumm = "!f() { local curBranch=$(git rev-parse --abbrev-ref HEAD) && git stash save && git fetch upstream && git checkout ${defaultBranch} && git merge upstream/${defaultBranch} && git checkout $curBranch && git stash pop; }; f";
              # Fetch upstream, merge the default branch, rebase the current branch.
              furb = "!f() { local curBranch=$(git rev-parse --abbrev-ref HEAD) && git stash save && git fetch upstream && git checkout ${defaultBranch} && git merge upstream/${defaultBranch} && git checkout $curBranch && git stash pop && git rebase -i ${defaultBranch}; }; f";
              fuub = "!f() { local curBranch=$(git rev-parse --abbrev-ref HEAD) && git fetch upstream && git merge upstream/$curBranch; }; f";
              fo = "!f() { git fetch origin $1:$1; }; f";

              # Commit
              c = "commit";
              cm = "commit -m";
              cmi = "commit --no-verify -m";
              cam = "commit -a -m";
              amend = "commit --amend --no-edit";
              ca = "commit --amend";
              wip = "commit -m wip --no-verify";

              # Move pointer
              prev = "checkout HEAD~1";
              next = "checkout HEAD@{1}";
              unstage = "reset HEAD";

              # Log and diffs
              ref = "reflog";
              lgg = "log --graph --pretty=format:'%Cred%h %C(reset)%C(dim)%ad%Creset %s%C(yellow)%d%C(reset) %C(blue)<%an> %Cgreen(%cr)%Creset' --abbrev-commit --date=short";
              adog = "log --all --decorate --oneline --graph";
              d = "diff";
              # Compare the current branch with its remote branch.
              dr = "!f() { local curBranch=$(git rev-parse --abbrev-ref HEAD) && git diff origin/$curBranch $curBranch; }; f";
              diffr = "diff --irreversible-delete --find-copies  --find-copies-harder --ignore-space-at-eol --ignore-space-change --ignore-all-space";
              diffs = "diff --irreversible-delete --find-copies  --find-copies-harder --ignore-space-at-eol --ignore-space-change --ignore-all-space --staged";
              dpf = "diff HEAD^ --name-only";
              ds = "show";
              dt = "difftool";
              dtd = "difftool -d";
              last = "!f() { git diff HEAD 'HEAD@{$1 ago}'; }; f";
              latest = "for-each-ref --sort=committerdate refs/heads/ --format='${latestFormat}'";

              # Push and pull
              p = "push";
              pf = "push --force-with-lease --force-if-includes";
              po = "!git push --set-upstream origin \"$(git rev-parse --abbrev-ref HEAD)\"";
              up = "pull";
              pl = "pull";
              prm = "!f() { git pull --rebase origin ${defaultBranch}; }; f";

              # Cleanup
              prune = "fetch --prune";
              dbr = "!f() { git branch -D $1; git push origin :$1;}; f";
              dtag = "!f() { git tag -d $1; git push origin :$1;}; f";

              # Stash
              s = "stash";
              sl = "stash list";
              ss = "stash save";
              sd = "stash drop";
              ssu = "stash save --include-untracked";
              ssp = "stash --patch";
              sp = "stash pop";
              sa = "stash apply";
              sw = "stash show -p";

              # Rebase
              r = "rebase";
              ra = "rebase --abort";
              rs = "rebase --skip";
              rc = "rebase --continue";
              ri = "rebase -i";
              rim = "!f() { git rebase -i ${defaultBranch}; }; f";
              rbm = "!f() { git rebase ${defaultBranch}; }; f";
              # ro: rebase this branch from parent $1 onto parent $2.
              ro = "!f() { git rebase --onto $1 $2 \"$(git rev-parse --abbrev-ref HEAD)\" ;}; f";
              rom = "!f() { git rebase --onto $() $1 \"$(git rev-parse --abbrev-ref HEAD)\" ;}; f";
              romm = "!f() { git rebase --onto main $1 \"$(git rev-parse --abbrev-ref HEAD)\" ;}; f";
              rum = "!f() { git rebase upstream/${defaultBranch}; }; f";

              # Rewrite
              squash-last = "!f() { git reset --soft HEAD~\"$1\" && git commit -m \"$(git log --format=%B --reverse HEAD..HEAD@{1})\"; }; f";
              squash-last-ignore = "!f() { git reset --soft HEAD~\"$1\" && git commit --no-verify -m \"$(git log --format=%B --reverse HEAD..HEAD@{1})\"; }; f";

              # Tags
              tdl = "tag -d";
              td = "!f() { git tag -d $1; git push origin :$1;}; f";
              tm = "tag -m";
              t = "tag";

              # Merge
              m = "merge";
              ma = "merge --abort";
              ms = "merge --skip";
              mc = "merge --continue";
              mum = "!f() { git merge upstream/${defaultBranch}; }; f";

              # Cherry-pick
              cp = "cherry-pick";
              cpa = "cherry-pick --abort";
              cps = "cherry-pick --skip";
              cpc = "cherry-pick --continue";

              # misc
              # Add to the .gitignore of the current directory.
              ignore = "!cd -- \${GIT_PREFIX:-.}; f() { echo \"$1\" >> .gitignore; }; f";
            }
            // cfg.extraAliases;

          # Do not produce whitespace conflicts.
          apply.ignoreWhitespace = "change";
          branch.autosetuprebase = "always";

          mergetool = {
            keepBackup = false;
          };
          merge = {
            ff = "only";
            conflictstyle = "diff3";
          };

          # `color.branch/diff/status = auto` are git's defaults (color.ui) and
          # cannot sit next to the `[color "branch"]` subsections in one attrset.
          color = {
            branch = {
              current = "yellow bold";
              local = "green bold";
              remote = "cyan bold";
            };
            diff = {
              meta = "yellow bold";
              frag = "magenta bold";
              old = "red bold";
              new = "green bold";
              whitespace = "red reverse";
            };
            status = {
              added = "green bold";
              changed = "yellow bold";
              untracked = "blue bold";
            };
          };

          commit =
            {verbose = true;}
            // lib.optionalAttrs signing {gpgsign = true;};
          tag =
            {verbose = true;}
            // lib.optionalAttrs signing {gpgsign = true;};

          core = {
            pager = "less";
            editor = "nvim";
          };

          credential.helper = "cache";

          diff = {
            algorithm = "histogram";
            indentHeuristic = true;
            # See camel case as separate words.
            wordRegex = "[A-Z][a-z]*|[a-z]+|[^[:space:]]";
            colorMoved = "zebra";
          };

          fetch.prune = true;
          pull = {
            ff = "only";
            rebase = true;
          };
          push = {
            default = "simple";
            followTags = true;
          };
          rebase = {
            autoStash = true;
            autoSquash = true;
            updateRefs = true;
          };
          status.showUntrackedFiles = "all";
          help.autocorrect = 1;
          init.defaultBranch = "main";
          hub.protocol = "git";
          tar."tar.xz".command = "xz -c";
        };
      };
    }

    (lib.mkIf named {
      programs.git.settings = {
        user.name = cfg.name;
        alias = {
          cycle = "!git log ${defaultBranch} --since='13 days ago' --pretty=format:'%h %ad | %s' --date=short --author=\"$(git config user.name)\"";
          mylatest = "!f() { git for-each-ref --color --sort=committerdate refs/heads/ --format='${latestFormat}' | grep -i \"$(git config user.name)\" | tail -n 50; }; f";
        };
      };
    })
    (lib.mkIf (cfg.email != null) {programs.git.settings.user.email = cfg.email;})
    (lib.mkIf signing {programs.git.settings.user.signingkey = cfg.signingKey;})
    (lib.mkIf identified {
      programs.git.settings = {
        alias = {
          resign = "!f() { ${resignExec} $@; }; f";
          resign-om = "!f() { ${resignExec} origin/main $@; }; f";
          resign-head = "!f() { ${resignExec} HEAD^ $@; }; f";
        };
        format.signOff = true;
      };
    })
  ]);
}
