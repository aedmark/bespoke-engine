#!/bin/sh
# P49-06 (D-194): a generated project rebuilds its package when a file the script includes
# changes, though main.bespoke does not. Run by `zig build test-template` after the starter
# project's own builds:  tools/check_template_deps.sh <project dir> <zig>
set -eu
project=$1
zig=$2
cd "$project"
wasm=zig-out/web/template_check.wasm

printf '\ninclude "extra.bespoke"\n' >> scripts/main.bespoke
printf 'scene Extra:\n  marks: Spot\n' > scripts/extra.bespoke
"$zig" build web
before=$(sha256sum "$wasm" | cut -d' ' -f1)

# Only the included file changes; the build must notice through the dependency file.
printf 'scene Extra:\n  marks: Spot, Other\n' > scripts/extra.bespoke
"$zig" build web
after=$(sha256sum "$wasm" | cut -d' ' -f1)

if [ "$before" = "$after" ]; then
  echo "FAIL changing scripts/extra.bespoke did not rebuild $wasm" >&2
  exit 1
fi
echo "ok  an edit to an included script rebuilds the package ($wasm changed)"
