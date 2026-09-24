{...}: {
  programs.home-manager.enable = true;
  programs.terminalKit = {
    enable = true;
    shellIntegration = "sourced";
    clipboard = "osc52";
    theme.modeSource = "terminal";
    aiSkills.enable = true;
    packages.dev.enable = false;
    # No git identity (D22): the workspace keeps its own.
  };
}
