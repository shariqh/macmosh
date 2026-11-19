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

echo "check.sh: swift build"
swift build

echo "check.sh: swift test"
swift test

if [ -f host/macmosh-host ]; then
    echo "check.sh: shellcheck host/macmosh-host"
    shellcheck host/macmosh-host
fi

echo "check.sh: all checks passed"
