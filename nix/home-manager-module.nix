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
    home.packages = [
      package
      pkgs.direnv
      pkgs.nushell
    ];

    xdg.configFile."direnv/direnvrc".text = ''
      source ${package}/share/direnv/lib/nu-overlay.sh
    '';
  };
}
