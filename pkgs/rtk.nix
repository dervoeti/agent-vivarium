{ stdenv, lib, fetchurl }:

stdenv.mkDerivation rec {
  pname = "rtk";
  version = "0.43.0";

  src = fetchurl {
    url = "https://github.com/rtk-ai/rtk/releases/download/v${version}/rtk-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-/4oed2ZJbhdSkaha7KHcl8n/bfM+UeWJPR+8eP6ipgk=";
  };

  sourceRoot = ".";
  unpackPhase = ''tar xzf $src'';
  dontBuild = true;
  installPhase = ''install -m755 -D rtk $out/bin/rtk'';

  meta = with lib; {
    homepage = "https://github.com/rtk-ai/rtk";
    description = "High-performance CLI proxy that reduces LLM token consumption";
    platforms = platforms.linux;
  };
}
