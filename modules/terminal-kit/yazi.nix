# yazi with the enfocado flavors.
{
  config,
  lib,
  pkgs,
  terminalKitStyle,
  ...
}: let
  cfg = config.programs.terminalKit;
  style = terminalKitStyle;
  tomlFormat = pkgs.formats.toml {};
  palettes = style.palettes.enfocado;
  tomlOverrideType = lib.types.submodule {
    options = {
      shared = lib.mkOption {
        type = tomlFormat.type;
        default = {};
        description = "TOML attributes merged into both generated light and dark theme files.";
      };
      light = lib.mkOption {
        type = tomlFormat.type;
        default = {};
        description = "TOML attributes merged only into the generated light theme file.";
      };
      dark = lib.mkOption {
        type = tomlFormat.type;
        default = {};
        description = "TOML attributes merged only into the generated dark theme file.";
      };
    };
  };
  mergeModeAttrs = base: ext: mode:
    lib.recursiveUpdate base (lib.recursiveUpdate ext.shared ext.${mode});
  toToml = attrs: builtins.readFile (tomlFormat.generate "theme.toml" attrs);
in {
  # Declared here, next to its only reader (the option type needs pkgs).
  options.programs.terminalKit.yazi.flavorOverrides = lib.mkOption {
    type = tomlOverrideType;
    default = {};
    description = "TOML overrides merged into generated Yazi flavor files.";
  };

  config = lib.mkIf (cfg.enable && cfg.yazi.enable) (lib.mkMerge [
    {
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        shellWrapperName = "yy";
      };
    }

    (lib.mkIf cfg.theme.enable {
      programs.yazi.theme.flavor = {
        dark = "enfocado-dark";
        light = "enfocado-light";
      };

      programs.yazi.flavors = {
        enfocado-light = pkgs.writeTextDir "flavor.toml" (
          toToml (mergeModeAttrs (style.mkYaziFlavorAttrs palettes.light) cfg.yazi.flavorOverrides "light")
        );
        enfocado-dark = pkgs.writeTextDir "flavor.toml" (
          toToml (mergeModeAttrs (style.mkYaziFlavorAttrs palettes.dark) cfg.yazi.flavorOverrides "dark")
        );
      };
    })
  ]);
}
