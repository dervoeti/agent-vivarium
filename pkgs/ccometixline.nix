{ lib, rustPlatform, fetchFromGitHub, pkg-config, openssl }:

rustPlatform.buildRustPackage rec {
  pname = "ccometixline";
  version = "1.1.1-unstable-2026-03-05";

  src = fetchFromGitHub {
    owner = "dervoeti";
    repo = "CCometixLine";
    rev = "a99dfc9c9591081724dc13c2397a9a6e64f28212";
    hash = "sha256-TeT2+EhAel9cxM6qtuHrBs7IYkV+U89/JV5hSI8+oJQ=";
  };

  cargoHash = "sha256-Sxsqh2/BbInFcCIoy0UFUYtWO8XVIbW58As3uJ/1z+w=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  # The binary is named ccometixline but we want it as ccline
  postInstall = ''
    mv $out/bin/ccometixline $out/bin/ccline
  '';

  meta = with lib; {
    description = "High-performance Claude Code statusline tool with Git integration";
    homepage = "https://github.com/dervoeti/CCometixLine";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
