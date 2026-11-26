#!/bin/bash
# Builds, tests and lints MacMosh. Stops at the first failure.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "check.sh: tests must not use the real folders"
# Tests use temporary folders (Paths.test, temporaryPaths()). Paths.standard() points at the
# real ~/Library/Application Support/MacMosh and ~/.ssh, which no test may read or write.
if matches=$(grep -rnF --include='*.swift' 'Paths.standard(' Tests); then
    echo "check.sh: FAILED: a test uses Paths.standard(), the real ~/.ssh and Application Support folders." >&2
    echo "check.sh: use Paths.test or temporaryPaths() instead. Found:" >&2
    echo "$matches" >&2
    exit 1
fi

echo "check.sh: the built-in copy of the host script is up to date"
# The macmosh binary carries its own copy of host/macmosh-host (Sources/MacMoshKit/Host/HostScriptSource.swift).
# This fails, naming scripts/embed-host-script.sh, when the script changed and the copy was not regenerated.
scripts/embed-host-script.sh --check

echo "check.sh: the icon's drawing script compiles with IconArt alone"
swiftc -typecheck scripts/draw-icon/main.swift Sources/MacMoshKit/Look/IconArt.swift

echo "check.sh: swift build"
swift build

echo "check.sh: swift test"
swift test

if [ -f host/macmosh-host ]; then
    echo "check.sh: shellcheck host/macmosh-host"
    shellcheck host/macmosh-host
fi
echo "check.sh: shellcheck scripts/embed-host-script.sh"
shellcheck scripts/embed-host-script.sh

echo "check.sh: shellcheck scripts/build-app.sh"
shellcheck scripts/build-app.sh

echo "check.sh: shellcheck scripts/make-icon.sh"
shellcheck scripts/make-icon.sh

echo "check.sh: shellcheck scripts/ci"
shellcheck scripts/ci/drive-menu.sh scripts/ci/drive-window.sh scripts/ci/try-select.sh scripts/ci/try-title.sh
shellcheck scripts/ci/icon-pictures.sh

echo "check.sh: shellcheck scripts/sitting-2"
shellcheck scripts/sitting-2/record.sh scripts/sitting-2/start.sh scripts/sitting-2/restart.sh

echo "check.sh: all checks passed"
