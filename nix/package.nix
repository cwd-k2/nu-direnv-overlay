{
  lib,
  stdenvNoCC,
  makeWrapper,
  direnv,
  nushell,
}:

stdenvNoCC.mkDerivation {
  pname = "nu-direnv-overlay";
  version = "0.1.0";

  # Package the repository as-is. There is no build step; the output is a set of
  # hook files plus the helper CLI.
  src = lib.cleanSource ./..;

  # wrapProgram is used only for the CLI helper so it can find direnv/nushell
  # when invoked from minimal profiles.
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    # Nushell vendor autoload is linked into profiles by NixOS/Home Manager and
    # loaded by Nushell automatically in interactive shells.
    mkdir -p "$out/bin"
    mkdir -p "$out/share/direnv/lib"
    mkdir -p "$out/share/nushell/vendor/autoload"

    # direnv loads shell libraries from direnvrc; the Nushell file is consumed by
    # the parent interactive shell.
    cp direnv/nu-overlay.sh "$out/share/direnv/lib/nu-overlay.sh"
    cp nushell/nu-direnv-overlay.nu "$out/share/nushell/vendor/autoload/nu-direnv-overlay.nu"

    # NU_DIRENV_OVERLAY_PKG pins helper output to this store path even if the
    # wrapper is reached through a profile symlink.
    cp bin/nu-direnv-overlay "$out/bin/nu-direnv-overlay"
    chmod +x "$out/bin/nu-direnv-overlay"
    wrapProgram "$out/bin/nu-direnv-overlay" \
      --prefix PATH : ${lib.makeBinPath [ direnv nushell ]} \
      --set NU_DIRENV_OVERLAY_PKG "$out"

    runHook postInstall
  '';

  meta = {
    description = "Project-local Nushell overlays managed by direnv";
    homepage = "https://github.com/cwd-k2/nu-direnv-overlay";
    license = lib.licenses.mit;
    mainProgram = "nu-direnv-overlay";
    platforms = lib.platforms.unix;
  };
}
