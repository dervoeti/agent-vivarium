# Overlay that pins claude-code to a specific version using the GCS binary distribution.
# From 2.x onwards, claude-code is distributed as a precompiled binary (not npm).
# This mirrors the approach in nixpkgs HEAD.
final: prev: {
  claude-code = prev.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "claude-code";
    version = "2.1.202";

    src = prev.fetchurl {
      url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${finalAttrs.version}/linux-x64/claude";
      hash = "sha256-cVkCAiSYkts4BezVuGf4MfBLgSnqq9P5pb1LoWtSyDk=";
    };

    dontUnpack = true;
    dontBuild = true;
    dontStrip = true;

    nativeBuildInputs = [
      prev.makeBinaryWrapper
      prev.autoPatchelfHook
    ];

    strictDeps = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 $src $out/bin/claude

      wrapProgram $out/bin/claude \
        --set DISABLE_AUTOUPDATER 1 \
        --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
        --set DISABLE_INSTALLATION_CHECKS 1 \
        --set USE_BUILTIN_RIPGREP 0 \
        --prefix PATH : ${prev.lib.makeBinPath [
          prev.procps
          prev.ripgrep
          prev.bubblewrap
          prev.socat
        ]}

      runHook postInstall
    '';

    meta = {
      description = "Agentic coding tool that lives in your terminal";
      license = prev.lib.licenses.unfree;
      mainProgram = "claude";
      platforms = [ "x86_64-linux" ];
    };
  });
}
