self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nu-direnv-overlay;
  package = cfg.package;
in
{
  options.programs.nu-direnv-overlay = {
    enable = lib.mkEnableOption "project-local Nushell overlays managed by direnv";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.nu-direnv-overlay.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "The nu-direnv-overlay package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Home Manager installs the package and runtime tools in the user profile.
    # The user still needs their normal Nushell direnv hook; this module only
    # adds overlay support on top.
    home.packages = [
      package
      pkgs.direnv
      pkgs.nushell
    ];

    # Register the direnv-side `use nu-overlay` function for this user.
    # The Nushell-side hook is loaded from the package's vendor autoload path.
    xdg.configFile."direnv/direnvrc".text = ''
      source ${package}/share/direnv/lib/nu-overlay.sh
    '';
  };
}
