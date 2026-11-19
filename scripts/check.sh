#!/bin/bash
# Builds, tests and lints MacMosh. Stops at the first failure.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "check.sh: swift build"
swift build

echo "check.sh: swift test"
swift test

if [ -f host/macmosh-host ]; then
    echo "check.sh: shellcheck host/macmosh-host"
    shellcheck host/macmosh-host
fi

echo "check.sh: all checks passed"
