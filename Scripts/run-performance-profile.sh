#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PAPERS=${1:-3000}
PAGES=${2:-12}
ITERATIONS=${3:-40}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
REPORT="$ROOT/Benchmarks/research-atlas-performance-$STAMP.json"

if [ -d "/Applications/Xcode.app" ]; then
  SDK_DIRECTORY=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --show-sdk-path)
elif [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]; then
  SDK_DIRECTORY=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
else
  SDK_DIRECTORY=$(xcrun --show-sdk-path)
fi

cd "$ROOT"
CLANG_MODULE_CACHE_PATH=/private/tmp/research-atlas-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/research-atlas-swift-cache \
SDKROOT="$SDK_DIRECTORY" \
swift run --disable-sandbox \
  --configuration release \
  --scratch-path /private/tmp/research-atlas-performance-build \
  --cache-path /private/tmp/research-atlas-cache \
  --config-path /private/tmp/research-atlas-config \
  --security-path /private/tmp/research-atlas-security \
  ResearchAtlasPerformance \
  --papers "$PAPERS" \
  --pages-per-paper "$PAGES" \
  --iterations "$ITERATIONS" \
  --output "$REPORT"
