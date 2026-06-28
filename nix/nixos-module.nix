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
    # Install the hook package and the two runtime tools it cooperates with.
    # This module does not configure the user's normal Nushell direnv hook.
    environment.systemPackages = [
      package
      pkgs.nushell
    ];

    # Make share/nushell/vendor/autoload visible through the system profile so
    # Nushell can autoload the overlay-side hook.
    environment.pathsToLink = [
      "/share/nushell"
    ];

    # Let NixOS's upstream direnv module own /etc/direnv/direnvrc and append our
    # .envrc helper there. This avoids collisions with users that already enable
    # programs.direnv or set direnvrcExtra themselves.
    programs.direnv = {
      enable = lib.mkDefault true;
      direnvrcExtra = lib.mkAfter ''
        source ${package}/share/direnv/lib/nu-overlay.sh
      '';
    };
  };
}
