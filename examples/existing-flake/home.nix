# Your existing configuration, unchanged. ripgrep, jq and fzf are in the kit
# too; with `follows` they are the same store paths, so nothing collides.
{pkgs, ...}: {
  home = {
    username = "tester";
    homeDirectory = "/home/tester";
    stateVersion = "26.05";
    packages = [pkgs.ripgrep pkgs.jq];
  };
  programs.home-manager.enable = true;
  programs.fzf.enable = true;
}
