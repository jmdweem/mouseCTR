#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
bundle_dir="$project_dir/build/MouseAutoScroll.app"
contents_dir="$bundle_dir/Contents"
macos_dir="$contents_dir/MacOS"
sdk_path="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"

if [[ ! -d "$sdk_path" ]]; then
    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
fi

export SDKROOT="$sdk_path"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/ModuleCache"

cd "$project_dir"
xcrun swift build -c "$configuration" --disable-sandbox -debug-info-format none

binary_path="$(xcrun swift build -c "$configuration" --disable-sandbox --show-bin-path)/MouseAutoScroll"

rm -rf "$bundle_dir"
mkdir -p "$macos_dir"
cp "$binary_path" "$macos_dir/MouseAutoScroll"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

echo "$bundle_dir"
