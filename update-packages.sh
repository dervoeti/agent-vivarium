#!/usr/bin/env bash
# Updates custom packages in pkgs/ to their latest versions.
# Usage:
#   ./update-packages.sh              # update all packages
#   ./update-packages.sh claude-code  # update only claude-code
#   ./update-packages.sh rtk          # update only rtk
#   ./update-packages.sh stackablectl # update only stackablectl
#   ./update-packages.sh ccometixline # update only ccometixline
#   ./update-packages.sh antigravity  # update only antigravity
#   ./update-packages.sh opencode     # update only opencode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGS_DIR="$SCRIPT_DIR/pkgs"

# --- helpers ---

current_version() {
  grep -oP '(?<=version = ")[^"]+' "$1" | head -1
}

update_nix_version() {
  local file="$1" old="$2" new="$3"
  sed -i "s|version = \"${old}\";|version = \"${new}\";|" "$file"
}

update_nix_hash() {
  local file="$1" new_hash="$2"
  sed -i "s|hash = \"[^\"]*\";|hash = \"${new_hash}\";|" "$file"
}

update_nix_sha256() {
  local file="$1" new_hash="$2"
  sed -i "s|sha256 = \"[^\"]*\";|sha256 = \"${new_hash}\";|" "$file"
}

sri_hash() {
  nix hash convert --hash-algo sha256 --to sri "$1"
}

# --- claude-code ---

update_claude_code() {
  local FILE="$PKGS_DIR/claude-code-overlay.nix"
  local CURRENT_VERSION
  CURRENT_VERSION=$(current_version "$FILE")

  echo "==> claude-code (current: $CURRENT_VERSION)"

  local NEW_VERSION
  if [[ ${FORCE_VERSION:-} ]]; then
    NEW_VERSION="$FORCE_VERSION"
  else
    NEW_VERSION=$(curl -fsSL "https://registry.npmjs.org/@anthropic-ai/claude-code/latest" | jq -r '.version')
  fi

  # From 2.x the overlay pins the precompiled GCS binary (fetchurl + single hash).
  local URL="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${NEW_VERSION}/linux-x64/claude"

  echo "    fetching hash for $NEW_VERSION..."
  local NEW_HASH
  NEW_HASH=$(nix store prefetch-file --json "$URL" 2>/dev/null | jq -r '.hash')
  echo "    hash: $NEW_HASH"

  local CURRENT_HASH
  CURRENT_HASH=$(grep -oP '(?<=hash = ")[^"]+' "$FILE" | head -1)

  # Compare hash too: a version bump without a hash bump silently reuses the
  # old cached fixed-output binary (the derivation is keyed by expected hash).
  if [[ "$CURRENT_VERSION" == "$NEW_VERSION" && "$CURRENT_HASH" == "$NEW_HASH" ]]; then
    echo "    already at $NEW_VERSION"
    return
  fi

  echo "    updating to $NEW_VERSION"
  update_nix_version "$FILE" "$CURRENT_VERSION" "$NEW_VERSION"
  update_nix_hash "$FILE" "$NEW_HASH"

  echo "    done"
}

# --- rtk ---

update_rtk() {
  local FILE="$PKGS_DIR/rtk.nix"
  local CURRENT_VERSION
  CURRENT_VERSION=$(current_version "$FILE")

  echo "==> rtk (current: $CURRENT_VERSION)"

  local NEW_VERSION
  NEW_VERSION=$(curl -fsSL "https://api.github.com/repos/rtk-ai/rtk/releases/latest" | jq -r '.tag_name' | sed 's/^v//')

  if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo "    already at $NEW_VERSION"
    return
  fi

  echo "    updating to $NEW_VERSION"
  local URL="https://github.com/rtk-ai/rtk/releases/download/v${NEW_VERSION}/rtk-x86_64-unknown-linux-musl.tar.gz"

  echo "    fetching hash..."
  local HASH
  HASH=$(sri_hash "$(nix-prefetch-url "$URL" 2>/dev/null)")
  echo "    hash: $HASH"

  update_nix_version "$FILE" "$CURRENT_VERSION" "$NEW_VERSION"
  update_nix_hash "$FILE" "$HASH"

  echo "    done"
}

# --- stackablectl ---

update_stackablectl() {
  local FILE="$PKGS_DIR/stackablectl.nix"
  local CURRENT_VERSION
  CURRENT_VERSION=$(current_version "$FILE")

  echo "==> stackablectl (current: $CURRENT_VERSION)"

  local NEW_VERSION
  # Releases are tagged as "stackablectl-X.Y.Z"
  NEW_VERSION=$(curl -fsSL "https://api.github.com/repos/stackabletech/stackable-cockpit/releases" \
    | jq -r '[.[] | select(.tag_name | startswith("stackablectl-"))][0].tag_name' \
    | sed 's/^stackablectl-//')

  if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo "    already at $NEW_VERSION"
    return
  fi

  echo "    updating to $NEW_VERSION"
  local URL="https://github.com/stackabletech/stackable-cockpit/releases/download/stackablectl-${NEW_VERSION}/stackablectl-x86_64-unknown-linux-gnu"

  echo "    fetching hash..."
  local HASH
  HASH=$(sri_hash "$(nix-prefetch-url "$URL" 2>/dev/null)")
  echo "    hash: $HASH"

  update_nix_version "$FILE" "$CURRENT_VERSION" "$NEW_VERSION"
  update_nix_sha256 "$FILE" "$HASH"

  echo "    done"
}

# --- antigravity ---

update_antigravity() {
  local FILE="$PKGS_DIR/antigravity.nix"
  local CURRENT_VERSION
  CURRENT_VERSION=$(current_version "$FILE")

  echo "==> antigravity (current: $CURRENT_VERSION)"

  # The download URL carries a per-version build-id suffix, so read both the
  # version and the full URL straight from the release manifest.
  local MANIFEST
  MANIFEST=$(curl -fsSL "https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json")

  local NEW_VERSION URL
  NEW_VERSION=$(echo "$MANIFEST" | jq -r '.version')
  URL=$(echo "$MANIFEST" | jq -r '.url')

  echo "    fetching hash for $NEW_VERSION..."
  local NEW_HASH
  NEW_HASH=$(nix store prefetch-file --json "$URL" 2>/dev/null | jq -r '.hash')
  echo "    hash: $NEW_HASH"

  local CURRENT_HASH
  CURRENT_HASH=$(grep -oP '(?<=sha256 = ")[^"]+' "$FILE" | head -1)

  if [[ "$CURRENT_VERSION" == "$NEW_VERSION" && "$CURRENT_HASH" == "$NEW_HASH" ]]; then
    echo "    already at $NEW_VERSION"
    return
  fi

  echo "    updating to $NEW_VERSION"
  update_nix_version "$FILE" "$CURRENT_VERSION" "$NEW_VERSION"
  update_nix_sha256 "$FILE" "$NEW_HASH"
  # URL contains slashes; use | as sed delimiter.
  sed -i "s|url = \"[^\"]*\";|url = \"${URL}\";|" "$FILE"

  echo "    done"
}

# --- opencode ---

update_opencode() {
  local FILE="$PKGS_DIR/opencode.nix"
  local CURRENT_VERSION
  CURRENT_VERSION=$(current_version "$FILE")

  echo "==> opencode (current: $CURRENT_VERSION)"

  local NEW_VERSION
  NEW_VERSION=$(curl -fsSL "https://api.github.com/repos/sst/opencode/releases/latest" | jq -r '.tag_name' | sed 's/^v//')

  if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo "    already at $NEW_VERSION"
    return
  fi

  echo "    updating to $NEW_VERSION"
  local URL="https://github.com/sst/opencode/releases/download/v${NEW_VERSION}/opencode-linux-x64.tar.gz"

  echo "    fetching hash..."
  local HASH
  HASH=$(sri_hash "$(nix-prefetch-url "$URL" 2>/dev/null)")
  echo "    hash: $HASH"

  update_nix_version "$FILE" "$CURRENT_VERSION" "$NEW_VERSION"
  update_nix_hash "$FILE" "$HASH"

  echo "    done"
}

# --- ccometixline ---

update_ccometixline() {
  local FILE="$PKGS_DIR/ccometixline.nix"
  local CURRENT_REV
  CURRENT_REV=$(grep -oP '(?<=rev = ")[^"]+' "$FILE")

  echo "==> ccometixline (current rev: ${CURRENT_REV:0:12})"

  local LATEST
  LATEST=$(curl -fsSL "https://api.github.com/repos/dervoeti/CCometixLine/commits/master" | jq -r '.sha')

  if [[ "$CURRENT_REV" == "$LATEST" ]]; then
    echo "    already at latest"
    return
  fi

  echo "    updating to ${LATEST:0:12}"

  # Fetch source hash
  local SRC_HASH
  SRC_HASH=$(nix-prefetch-url --unpack "https://github.com/dervoeti/CCometixLine/archive/${LATEST}.tar.gz" 2>/dev/null)
  SRC_HASH=$(sri_hash "$SRC_HASH")

  sed -i "s|rev = \"${CURRENT_REV}\"|rev = \"${LATEST}\"|" "$FILE"
  sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"${SRC_HASH}\"|" "$FILE"

  # Update version date
  local DATE
  DATE=$(date +%Y-%m-%d)
  sed -i "s|unstable-[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}|unstable-${DATE}|" "$FILE"

  # cargoHash must be updated manually — set to empty and let the build tell you
  sed -i 's|cargoHash = "sha256-[^"]*"|cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' "$FILE"

  echo "    source updated. cargoHash set to placeholder."
  echo "    Run 'nix build' and replace cargoHash with the correct hash from the error."
  echo "    done"
}

# --- main ---

TARGETS=("${@:-claude-code rtk stackablectl ccometixline antigravity opencode}")
if [[ $# -eq 0 ]]; then
  TARGETS=(claude-code rtk stackablectl ccometixline antigravity opencode)
fi

for target in "${TARGETS[@]}"; do
  case "$target" in
    claude-code)  update_claude_code ;;
    rtk)          update_rtk ;;
    stackablectl) update_stackablectl ;;
    ccometixline) update_ccometixline ;;
    antigravity)  update_antigravity ;;
    opencode)     update_opencode ;;
    *) echo "Unknown package: $target"; exit 1 ;;
  esac
done

echo ""
echo "Run 'nixos-rebuild switch --flake .#devVM' to apply."
