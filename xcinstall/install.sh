#!/bin/bash
# Installs an Xcode version with xcodes (https://github.com/XcodesOrg/xcodes) and selects it.
#
#   xcinstall/install.sh 16.2     install (if needed) and select Xcode 16.2
#   xcinstall/install.sh          use the version in ./.xcode-version
#
# Downloading Xcode needs an Apple ID: set XCODES_USERNAME and XCODES_PASSWORD.
# Apple asks for a 2FA code on new sessions and xcodes can only prompt for it interactively, so run this once
# by hand on a CI machine (the session is then cached in the keychain), or use a runner image that already
# has the Xcode you need (GitHub-hosted macOS runners do).
# Xcode ends up at /Applications/Xcode-<version>.app; scripts/build.sh picks it via .xcode-version.

export PATH="$(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin:$PATH"

VERSION="${1:-$(tr -d '[:space:]' < .xcode-version 2>/dev/null)}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: install.sh {XCODE_VERSION}   (or create a .xcode-version file)"
  echo "Example: install.sh 16.2"
  exit 1
fi

if ! which xcodes > /dev/null; then
  echo "[INSTALL.SH] Installing xcodes"
  brew install xcodes || exit 1
fi

if xcodes installed | grep -q "^$VERSION"; then
  echo "[INSTALL.SH] Xcode $VERSION already installed"
else
  if [[ -z "$XCODES_USERNAME" || -z "$XCODES_PASSWORD" ]]; then
    echo "[INSTALL.SH] Xcode $VERSION is not installed. To download it set a valid developer account:"
    echo "[INSTALL.SH]   export XCODES_USERNAME=XXX XCODES_PASSWORD=XXX"
    exit 1
  fi
  xcodes install "$VERSION" || exit 1
fi

xcodes select "$VERSION" || exit 1
sudo xcodebuild -runFirstLaunch || true
xcodebuild -version
