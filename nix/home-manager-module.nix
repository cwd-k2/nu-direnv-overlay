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
      pkgs.nushell
    ];

    # Let Home Manager's upstream direnv module own direnvrc and append our
    # .envrc helper there. This composes with users' existing stdlib content.
    programs.direnv = {
      enable = lib.mkDefault true;
      stdlib = lib.mkAfter ''
        source ${package}/share/direnv/lib/nu-overlay.sh
      '';
    };
  };
}
