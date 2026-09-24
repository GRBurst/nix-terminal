{lib}: let
  stripHash = color: lib.removePrefix "#" color;

  # i3 and Sway share the `client.*` colour-class vocabulary verbatim, down to
  # `client.placeholder`, which Sway's own manual does not document but its
  # parser accepts -- verified with `sway --validate`, which is also the gate
  # in `checks/eval-assertions.nix`. One renderer, two adapters: when i3 goes,
  # `mkI3Theme` goes with it and `mkSwayTheme` stays.
  mkClientColourTheme = palette: ''
    client.focused          ${palette.normal.blue}  ${palette.normal.blue}  ${palette.primary.background} ${palette.normal.magenta} ${palette.normal.blue}
    client.focused_inactive ${palette.bright.black} ${palette.bright.black} ${palette.normal.white} ${palette.normal.white} ${palette.bright.black}
    client.unfocused        ${palette.bright.black} ${palette.bright.black} ${palette.normal.white} ${palette.normal.white} ${palette.bright.black}
    client.urgent           ${palette.normal.red}   ${palette.normal.red}   ${palette.primary.background} ${palette.normal.red}      ${palette.normal.red}
    client.placeholder      ${palette.primary.background} ${palette.normal.green} ${palette.primary.foreground} ${palette.primary.background} ${palette.primary.background}
  '';
  mkNoctaliaVariant = palette: let
    isLight = (palette.polarity or "dark") == "light";
    bg = palette.primary.background;
    fg = palette.primary.foreground;
    muted =
      if isLight
      then palette.normal.white
      else palette.bright.black;
  in {
    mSurface = bg;
    mSurfaceVariant = palette.normal.black;
    mOnSurface = fg;
    mOnSurfaceVariant = muted;
    mOutline = palette.bright.black;
    mShadow = bg;

    mPrimary = palette.normal.magenta;
    mOnPrimary = bg;
    mSecondary = palette.normal.blue;
    mOnSecondary = bg;
    mTertiary = palette.normal.cyan;
    mOnTertiary = bg;
    mHover = palette.bright.magenta;
    mOnHover = bg;
    mError = palette.normal.red;
    mOnError = bg;

    terminal = {
      background = bg;
      foreground = fg;
      cursor = fg;
      cursorText = bg;
      selectionBg = palette.bright.black;
      selectionFg = fg;
      normal = {
        inherit (palette.normal) black red green yellow blue magenta cyan white;
      };
      bright = {
        inherit (palette.bright) black red green yellow blue magenta cyan white;
      };
    };
  };
in {
  palettes.enfocado = import ./enfocado.nix;

  inherit stripHash mkNoctaliaVariant;

  toBase16 = palette: let
    isLight = (palette.polarity or "dark") == "light";
  in {
    base00 = stripHash palette.primary.background;
    base01 = stripHash palette.normal.black;
    base02 = stripHash palette.bright.black;
    base03 = stripHash (
      if isLight
      then palette.normal.white # dim_0 — comments / muted text
      else palette.bright.black # bg_2 — selection bg
    );
    base04 = stripHash palette.primary.foreground;
    base05 = stripHash palette.primary.foreground;
    base06 = stripHash palette.bright.white;
    base07 = stripHash palette.bright.white;
    base08 = stripHash palette.normal.red;
    base09 = stripHash palette.bright.red;
    base0A = stripHash palette.normal.yellow;
    base0B = stripHash palette.normal.green;
    base0C = stripHash palette.normal.cyan;
    base0D = stripHash palette.normal.blue;
    base0E = stripHash palette.normal.magenta;
    base0F = stripHash palette.normal.violet;
  };

  # Noctalia v5 custom palette.
  #
  # Shape verified against the Home Manager module's own golden fixture,
  # tests/modules/programs/noctalia/expected-custom-palette.json: sixteen `m*`
  # roles plus a `terminal` subtree. Written as ONE palette carrying BOTH
  # variants rather than two single-variant palettes, because that is how the
  # format is designed and because it is the only arrangement that keeps
  # Noctalia's own notion of the mode in step with the colours it shows --
  # swapping two separate palettes via `color-scheme-set` would leave
  # `theme.mode` untouched, so the shell would believe it was dark while
  # rendering light.
  #
  # Role mapping follows the same reading of the palette as toBase16, so the
  # shell agrees with every other generated artifact:
  #   surface      = primary.background        (bg_0)
  #   surfaceVar   = normal.black              (bg_1)
  #   onSurface    = primary.foreground        (fg_0)
  #   onSurfaceVar = dim/muted text, polarity-dependent exactly as base03
  #   outline      = bright.black              (bg_2)
  #   primary/secondary/tertiary = magenta/blue/cyan, matching the accent
  #                  assignment used by the rofi, waybar and yazi renderers
  #   error        = normal.red
  #   on*          = background, i.e. text drawn ON an accent is surface-coloured

  # Both variants in one palette, ready for programs.noctalia.customPalettes.
  toNoctaliaPalette = palettes: {
    dark = mkNoctaliaVariant palettes.dark;
    light = mkNoctaliaVariant palettes.light;
  };

  mkAlacrittyThemeAttrs = palette: {
    colors = {
      primary = {
        background = palette.primary.background;
        foreground = palette.primary.foreground;
      };
      normal = {
        black = palette.normal.black;
        red = palette.normal.red;
        green = palette.normal.green;
        yellow = palette.normal.yellow;
        blue = palette.normal.blue;
        magenta = palette.normal.magenta;
        cyan = palette.normal.cyan;
        white = palette.normal.white;
      };
      bright = {
        black = palette.bright.black;
        red = palette.bright.red;
        green = palette.bright.green;
        yellow = palette.bright.yellow;
        blue = palette.bright.blue;
        magenta = palette.bright.magenta;
        cyan = palette.bright.cyan;
        white = palette.bright.white;
      };
    };
  };

  mkAlacrittyTheme = palette: ''
    [colors.primary]
    background = "${palette.primary.background}"
    foreground = "${palette.primary.foreground}"

    [colors.normal]
    black = "${palette.normal.black}"
    red = "${palette.normal.red}"
    green = "${palette.normal.green}"
    yellow = "${palette.normal.yellow}"
    blue = "${palette.normal.blue}"
    magenta = "${palette.normal.magenta}"
    cyan = "${palette.normal.cyan}"
    white = "${palette.normal.white}"

    [colors.bright]
    black = "${palette.bright.black}"
    red = "${palette.bright.red}"
    green = "${palette.bright.green}"
    yellow = "${palette.bright.yellow}"
    blue = "${palette.bright.blue}"
    magenta = "${palette.bright.magenta}"
    cyan = "${palette.bright.cyan}"
    white = "${palette.bright.white}"
  '';

  mkKittyTheme = palette: ''
    background ${palette.primary.background}
    foreground ${palette.primary.foreground}

    color0 ${palette.normal.black}
    color1 ${palette.normal.red}
    color2 ${palette.normal.green}
    color3 ${palette.normal.yellow}
    color4 ${palette.normal.blue}
    color5 ${palette.normal.magenta}
    color6 ${palette.normal.cyan}
    color7 ${palette.normal.white}

    color8 ${palette.bright.black}
    color9 ${palette.bright.red}
    color10 ${palette.bright.green}
    color11 ${palette.bright.yellow}
    color12 ${palette.bright.blue}
    color13 ${palette.bright.magenta}
    color14 ${palette.bright.cyan}
    color15 ${palette.bright.white}
  '';

  mkRofiTheme = palette: ''
    * {
      background: ${palette.primary.background};
      foreground: ${palette.primary.foreground};
      accent: ${palette.normal.blue};
      muted: ${palette.normal.white};
      urgent: ${palette.normal.red};

      background-color: @background;
      text-color: @foreground;
      border-color: @accent;
    }

    window {
      background-color: @background;
      border: 2px;
      border-color: @accent;
      padding: 8px;
    }

    mainbox {
      background-color: @background;
    }

    inputbar {
      background-color: @background;
      text-color: @foreground;
      padding: 6px;
    }

    prompt, entry {
      text-color: @foreground;
    }

    listview {
      background-color: @background;
      lines: 8;
    }

    element {
      background-color: @background;
      text-color: @foreground;
      margin: 0;
      padding: 0;
      border: 0;
    }

    element selected {
      background-color: @accent;
      text-color: @background;
    }

    element-text, element-icon {
      background-color: transparent;
      text-color: inherit;
    }

    element urgent {
      background-color: @urgent;
      text-color: @background;
    }

    mode-switcher {
      background-color: @background;
    }

    button selected {
      background-color: @accent;
      text-color: @background;
    }
  '';

  # zathurarc `set` lines, pulled in through an `include` of the current link.
  # recolor-* only matter when the user toggles recolouring (Ctrl-r); they map
  # the page onto the palette so a recoloured PDF matches the mode.
  mkZathuraTheme = palette: ''
    set default-bg "${palette.primary.background}"
    set default-fg "${palette.primary.foreground}"
    set statusbar-bg "${palette.normal.black}"
    set statusbar-fg "${palette.primary.foreground}"
    set inputbar-bg "${palette.primary.background}"
    set inputbar-fg "${palette.primary.foreground}"
    set notification-bg "${palette.primary.background}"
    set notification-fg "${palette.primary.foreground}"
    set notification-error-bg "${palette.primary.background}"
    set notification-error-fg "${palette.normal.red}"
    set notification-warning-bg "${palette.primary.background}"
    set notification-warning-fg "${palette.normal.yellow}"
    set completion-bg "${palette.normal.black}"
    set completion-fg "${palette.primary.foreground}"
    set completion-group-bg "${palette.normal.black}"
    set completion-group-fg "${palette.normal.blue}"
    set completion-highlight-bg "${palette.normal.blue}"
    set completion-highlight-fg "${palette.primary.background}"
    set index-bg "${palette.primary.background}"
    set index-fg "${palette.primary.foreground}"
    set index-active-bg "${palette.normal.blue}"
    set index-active-fg "${palette.primary.background}"
    set highlight-color "${palette.normal.yellow}"
    set highlight-active-color "${palette.normal.blue}"
    set recolor-lightcolor "${palette.primary.background}"
    set recolor-darkcolor "${palette.primary.foreground}"
  '';

  mkYaziFlavorAttrs = palette: {
    mgr = {
      cwd.fg = palette.normal.blue;
      hovered = {
        fg = palette.primary.background;
        bg = palette.normal.blue;
      };
      preview_hovered = {
        fg = palette.primary.background;
        bg = palette.normal.blue;
      };
    };
    status.overall = {
      fg = palette.primary.foreground;
      bg = palette.primary.background;
    };
    mode = {
      normal_main = {
        fg = palette.primary.background;
        bg = palette.normal.blue;
      };
      select_main = {
        fg = palette.primary.background;
        bg = palette.normal.magenta;
      };
      unset_main = {
        fg = palette.primary.background;
        bg = palette.normal.red;
      };
    };
    filetype.rules = [
      {
        mime = "image/*";
        fg = palette.normal.yellow;
      }
      {
        mime = "{audio,video}/*";
        fg = palette.normal.orange;
      }
      {
        mime = "application/{zip,rar,7z*,tar,gzip,xz}";
        fg = palette.normal.red;
      }
      {
        mime = "text/*";
        fg = palette.normal.violet;
      }
      {
        url = "*/";
        fg = palette.normal.blue;
      }
    ];
  };

  mkYaziFlavor = palette: ''
    [mgr]
    cwd = { fg = "${palette.normal.blue}" }
    hovered = { fg = "${palette.primary.background}", bg = "${palette.normal.blue}" }
    preview_hovered = { fg = "${palette.primary.background}", bg = "${palette.normal.blue}" }

    [status]
    overall = { fg = "${palette.primary.foreground}", bg = "${palette.primary.background}" }

    [mode]
    normal_main = { fg = "${palette.primary.background}", bg = "${palette.normal.blue}" }
    select_main = { fg = "${palette.primary.background}", bg = "${palette.normal.magenta}" }
    unset_main = { fg = "${palette.primary.background}", bg = "${palette.normal.red}" }

    [filetype]
    rules = [
      { mime = "image/*",                                fg = "${palette.normal.yellow}" },
      { mime = "{audio,video}/*",                        fg = "${palette.normal.orange}" },
      { mime = "application/{zip,rar,7z*,tar,gzip,xz}", fg = "${palette.normal.red}" },
      { mime = "text/*",                                 fg = "${palette.normal.violet}" },
      { url = "*/",                                      fg = "${palette.normal.blue}" },
    ]
  '';

  mkI3StatusThemeAttrs = palette: {
    idle_bg = palette.primary.background;
    idle_fg = palette.primary.foreground;
    info_bg = palette.primary.background;
    info_fg = palette.normal.blue;
    good_bg = palette.primary.background;
    good_fg = palette.normal.green;
    warning_bg = palette.primary.background;
    warning_fg = palette.normal.yellow;
    critical_bg = palette.primary.background;
    critical_fg = palette.normal.red;
    separator = "";
    separator_bg = palette.primary.background;
    separator_fg = palette.normal.white;
    alternating_tint_bg = "#00000000";
    alternating_tint_fg = "#00000000";
  };

  mkI3StatusTheme = palette: ''
    idle_bg = "${palette.primary.background}"
    idle_fg = "${palette.primary.foreground}"
    info_bg = "${palette.primary.background}"
    info_fg = "${palette.normal.blue}"
    good_bg = "${palette.primary.background}"
    good_fg = "${palette.normal.green}"
    warning_bg = "${palette.primary.background}"
    warning_fg = "${palette.normal.yellow}"
    critical_bg = "${palette.primary.background}"
    critical_fg = "${palette.normal.red}"
    separator = ""
    separator_bg = "${palette.primary.background}"
    separator_fg = "${palette.normal.white}"
    alternating_tint_bg = "#00000000"
    alternating_tint_fg = "#00000000"
  '';

  mkDunstConfig = palette: fontCfg: ''
    [global]
        monitor = 0
        follow = keyboard
        origin = top-right
        offset = 12x42
        width = 420
        height = 300
        notification_limit = 5
        corner_radius = 4
        frame_width = 2
        separator_height = 2
        padding = 10
        horizontal_padding = 12
        gap_size = 6
        font = "${fontCfg.families.sansSerif.name} ${toString fontCfg.sizes.notification.body}"
        markup = full
        format = "<b>%s</b>\n%b"
        icon_position = left
        max_icon_size = 48
        frame_color = "${palette.normal.blue}"
        separator_color = frame

    [urgency_low]
        background  = "${palette.primary.background}"
        foreground  = "${palette.normal.white}"
        frame_color = "${palette.normal.orange}"
        timeout = 5

    [urgency_normal]
        background = "${palette.primary.background}"
        foreground = "${palette.primary.foreground}"
        timeout = 8

    [urgency_critical]
        background = "${palette.primary.background}"
        foreground = "${palette.normal.red}"
        frame_color = "${palette.normal.red}"
        timeout = 0
  '';

  mkI3Theme = mkClientColourTheme;
  mkSwayTheme = mkClientColourTheme;

  mkWaybarCss = palette: fontFamily: ''
    * {
      font-family: "${fontFamily}", monospace;
      font-size: 13px;
    }

    window#waybar {
      background-color: ${palette.primary.background};
      color: ${palette.primary.foreground};
    }

    #workspaces button {
      padding: 0 5px;
      color: ${palette.primary.foreground};
      border-bottom: 2px solid transparent;
    }

    #workspaces button.active {
      color: ${palette.normal.blue};
      border-bottom: 2px solid ${palette.normal.blue};
    }

    #clock, #pulseaudio, #network, #cpu, #memory, #battery, #tray {
      padding: 0 8px;
    }
  '';

  mkHyprlandTheme = palette: ''
    general {
      col.active_border   = rgba(${stripHash palette.normal.blue}ee) rgba(${stripHash palette.normal.violet}ee) 45deg
      col.inactive_border = rgba(${stripHash palette.bright.black}aa)
    }
  '';
}
