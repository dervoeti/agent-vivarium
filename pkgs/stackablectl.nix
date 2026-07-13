{ stdenv, lib, pkgs, autoPatchelfHook }:

stdenv.mkDerivation rec {
  pname = "stackablectl";
  version = "1.4.0";

  src = pkgs.fetchurl {
    url = "https://github.com/stackabletech/stackable-cockpit/releases/download/stackablectl-${version}/stackablectl-x86_64-unknown-linux-gnu";
    sha256 = "sha256-GombCyCddfZPlXsPRREebfJXyL6z3fH7GxlcOygoqk4=";
  };

  dontUnpack = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc ];

  sourceRoot = ".";
  installPhase = ''install -m755 -D $src $out/bin/stackablectl'';

  meta = with lib; {
    homepage = "https://stackable.tech";
    description = "Stackable CLI";
    platforms = platforms.linux;
  };
}
