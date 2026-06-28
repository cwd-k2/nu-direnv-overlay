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
      pkgs.direnv
      pkgs.nushell
    ];

    # Make share/nushell/vendor/autoload visible through the system profile so
    # Nushell can autoload the overlay-side hook.
    environment.pathsToLink = [
      "/share/nushell"
    ];

    # System direnvrc registers the `use nu-overlay` .envrc function, then
    # chains user direnv customizations. DIRENV_CONFIG below points direnv at
    # /etc/direnv so this system file is consistently loaded.
    environment.etc."direnv/direnvrc".text = ''
      source ${package}/share/direnv/lib/nu-overlay.sh

      # Preserve normal user extension points even though DIRENV_CONFIG is
      # redirected to /etc/direnv.
      user_direnv_config="''${XDG_CONFIG_HOME:-$HOME/.config}/direnv"
      for lib in "$user_direnv_config/lib/"*.sh; do
        [ -f "$lib" ] && source "$lib"
      done
      [ -f "$user_direnv_config/direnvrc" ] && source "$user_direnv_config/direnvrc"
      [ -f "$HOME/.direnvrc" ] && source "$HOME/.direnvrc"
    '';

    # direnv normally reads ~/.config/direnv. Pointing it at /etc/direnv lets the
    # module provide a system-wide library while the direnvrc above re-includes
    # per-user config files.
    environment.sessionVariables.DIRENV_CONFIG = "/etc/direnv";
  };
}
