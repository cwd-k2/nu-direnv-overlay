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

  src = lib.cleanSource ./..;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    mkdir -p "$out/share/direnv/lib"
    mkdir -p "$out/share/nushell/vendor/autoload"

    cp direnv/nu-overlay.sh "$out/share/direnv/lib/nu-overlay.sh"
    cp nushell/nu-direnv-overlay.nu "$out/share/nushell/vendor/autoload/nu-direnv-overlay.nu"

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
