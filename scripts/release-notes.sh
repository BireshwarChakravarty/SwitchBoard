#!/bin/bash
# Prints the release notes for a version: its section of CHANGELOG.md,
# followed by install instructions. Fails if the changelog has no entry for
# it, so a release can't go out undocumented.
#
# Usage: scripts/release-notes.sh 2.0.1
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release-notes.sh <version>}"

NOTES="$(awk -v heading="## [$VERSION]" '
    index($0, heading) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d')"

if [ -z "${NOTES//[[:space:]]/}" ]; then
    echo "error: CHANGELOG.md has no entry for $VERSION" >&2
    exit 1
fi

REPO="https://github.com/BireshwarChakravarty/SwitchBoard"
if [[ "$VERSION" == *-* ]]; then
    # A pre-release isn't "latest": link to this release's own download.
    DOWNLOAD="$REPO/releases/download/v$VERSION/Switchboard.zip"
    printf '%s\n\n' "**Pre-release** for testing. The latest stable release stays the default download."
else
    DOWNLOAD="$REPO/releases/latest/download/Switchboard.zip"
fi

printf '%s\n' "$NOTES"
cat <<INSTALL

---

**Install or update:** download **Switchboard.zip** below, unzip it and move
**Switchboard.app** to Applications, then run
\`xattr -dr com.apple.quarantine /Applications/Switchboard.app\` (the app is
ad-hoc signed, not notarized). Or in Terminal:

\`\`\`bash
pkill -x Switchboard; rm -rf /Applications/Switchboard.app && curl -L -o ~/Downloads/Switchboard.zip $DOWNLOAD && unzip -o ~/Downloads/Switchboard.zip -d /Applications && xattr -dr com.apple.quarantine /Applications/Switchboard.app && open /Applications/Switchboard.app
\`\`\`

Settings and permissions carry over. See the
[README](https://github.com/BireshwarChakravarty/SwitchBoard#readme) for
setup and the [changelog](https://github.com/BireshwarChakravarty/SwitchBoard/blob/main/CHANGELOG.md)
for every change.
INSTALL
