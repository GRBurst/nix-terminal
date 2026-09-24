# The two test configurations and the check helpers (Snippet 3).
#
# Both are built with the real `homeManagerConfiguration` (PD5) and without
# any Stylix module (R2). Reading `.config` runs Home Manager's assertion
# check, so a failed assertion fails every check that uses it.
{
  pkgs,
  lib,
  self,
  home-manager,
}: rec {
  mkHome = modules:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [self.homeModules.default] ++ modules;
    };

  # Cₒ: every option on, owned shell integration, user `tester`.
  ownedHome = mkHome [
    {
      home = {
        username = "tester";
        homeDirectory = "/home/tester";
        stateVersion = "26.05";
      };
      programs.terminalKit = {
        enable = true;
        packages.dev.enable = true;
        aiSkills.enable = true;
        git = {
          name = "tester";
          email = "tester@example.invalid";
          signingKey = "DEADBEEF";
          githubUser = "tester";
          extraAliases.tk-probe = "status";
        };
        zsh.extraAliases.tk-probe = "true";
        nvf.extraKeymaps = [
          {
            mode = ["n"];
            key = "<leader>tk";
            action = "<cmd>echo<cr>";
            desc = "tk-probe";
          }
        ];
        bash.extraAliases.tk-probe = "true";
      };
    }
  ];

  # Cₜ: the template, unedited.
  templateHome = let
    u = import ../templates/coder/user.nix;
  in
    mkHome [
      {
        home = {
          username = u.name;
          inherit (u) homeDirectory stateVersion;
        };
      }
      ../templates/coder/home.nix
    ];

  Co = ownedHome.config;
  Ct = templateHome.config;

  # A failing condition is a build-time failure, so `--keep-going` reports
  # every check instead of stopping at the first eval error.
  mkCheck = name: cond: msg:
    pkgs.runCommand name {} (
      if cond
      then "touch $out"
      else "printf '%s\\n' ${lib.escapeShellArg msg} >&2; exit 1"
    );

  targets = c: map (f: f.target) (lib.filter (f: f.enable) (lib.attrValues c.home.file));
}
