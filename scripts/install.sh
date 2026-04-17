#!/usr/bin/env bash
set -euo pipefail

REPO="pavlo-appodeal/claude-usage-bar"
ASSET="ClaudeUsageBar.dmg"
APP_NAME="ClaudeUsageBar.app"
INSTALL_DIR="/Applications"

echo "→ Fetching latest release..."
DOWNLOAD_URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"browser_download_url"' \
  | grep "${ASSET}" \
  | head -1 \
  | sed 's/.*"browser_download_url": "\(.*\)"/\1/')

if [ -z "$DOWNLOAD_URL" ]; then
  echo "✗ Could not find ${ASSET} in the latest release." >&2
  echo "  Check https://github.com/${REPO}/releases for available assets." >&2
  exit 1
fi

TMP_DMG=$(mktemp /tmp/ClaudeUsageBar-XXXXXX.dmg)
echo "→ Downloading $(basename "$DOWNLOAD_URL")..."
curl -fsSL --progress-bar -o "$TMP_DMG" "$DOWNLOAD_URL"

echo "→ Mounting disk image..."
MOUNT_POINT=$(mktemp -d /tmp/claude-usage-bar-XXXXXX)
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

echo "→ Installing to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}/${APP_NAME}"
cp -R "${MOUNT_POINT}/${APP_NAME}" "${INSTALL_DIR}/"

echo "→ Removing quarantine attribute..."
xattr -cr "${INSTALL_DIR}/${APP_NAME}"

echo "→ Cleaning up..."
hdiutil detach "$MOUNT_POINT" -quiet
rm -f "$TMP_DMG"
rmdir "$MOUNT_POINT" 2>/dev/null || true

echo ""
echo "✓ Installed ${APP_NAME} to ${INSTALL_DIR}"
echo ""
echo "Launch it from /Applications or Spotlight."
echo "If macOS still shows a security prompt, go to:"
echo "  System Settings → Privacy & Security → Open Anyway"
