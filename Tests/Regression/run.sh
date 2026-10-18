#!/bin/bash
set -euo pipefail
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [/path/to/Sweep/Sources/Sweep/Sweep.swift]" >&2
    exit 2
fi
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
sweep_source="${1:-$repo_root/.build/SourcePackages/checkouts/Sweep/Sources/Sweep/Sweep.swift}"
if [ ! -f "$sweep_source" ]; then
    echo "Sweep source not found. Build the Xcode project first or supply its resolved Sweep.swift path." >&2
    exit 2
fi
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -emit-module -emit-library -module-name Sweep "$sweep_source" \
    -o "$test_dir/libSweep.dylib" -emit-module-path "$test_dir/Sweep.swiftmodule"
xcrun swiftc -I "$test_dir" -L "$test_dir" -lSweep \
    "$repo_root/Quality/CMPlayerStuff.swift" "$repo_root/Tests/Regression/main.swift" \
    "$repo_root/Quality/PlaybackState.swift" \
    "$repo_root/Quality/SourceAudioFormat.swift" \
    -o "$test_dir/regression"
DYLD_LIBRARY_PATH="$test_dir" "$test_dir/regression"
