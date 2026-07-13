{ stdenv, lib, pkgs, autoPatchelfHook }:
let
  version = "1.1.1";
  # Full URL taken verbatim from the release manifest (build-id suffix varies per version).
  # See update-packages.sh; manifest: https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json
  url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.1-6269367663591424/linux-x64/cli_linux_x64.tar.gz";
  sha256 = "sha256-LuFnhBzcmh19xaYk8fFbhO5du5S4WvZipymRGMtLFYY=";
in
stdenv.mkDerivation {
  pname = "antigravity-cli";
  inherit version;

  src = pkgs.fetchurl { inherit url sha256; };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc
  ];

  sourceRoot = ".";

  # tarball contains a single binary named `antigravity`; CLI command is `agy`
  installPhase = ''
    install -m755 -D antigravity $out/bin/agy
    ln -s agy $out/bin/antigravity
  '';

  meta = with lib; {
    homepage = "https://antigravity.google";
    description = "Antigravity CLI (agy) - Google Antigravity command-line tool";
    platforms = [ "x86_64-linux" ];
    # Proprietary Google software - not OSS
    license = licenses.unfree;
    mainProgram = "agy";
  };
}
