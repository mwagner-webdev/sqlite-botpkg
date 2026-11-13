#!/bin/bash
# Build dist/sqlite-VERSION.botpkg from sqlite/ plus per-target SQLite archives.
#
#   BOT=/path/to/botlish scripts/pack.sh [--linux-x86_64 ARCHIVE] [--macos-aarch64 ARCHIVE] [--out DIR]
#
# Without --linux-x86_64 the Linux archive is built here with native/build.sh. The package is packed twice and the two
# artifacts must be byte-identical (the pack is deterministic). The archives are inputs, not outputs of the pack: a
# release holds the archives its CI built (see .github/workflows/ci.yml, job `package`).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOT=${BOT:-$ROOT/botlish}
OUT=$ROOT/dist
LINUX=""
MACOS=""
while [ $# -gt 0 ]; do
  case $1 in
    --linux-x86_64) LINUX=$2; shift 2;;
    --macos-aarch64) MACOS=$2; shift 2;;
    --out) OUT=$2; shift 2;;
    *) echo "unknown argument $1" >&2; exit 2;;
  esac
done
abs() { (cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")"); }
[ -z "$LINUX" ] || LINUX=$(abs "$LINUX")
[ -z "$MACOS" ] || MACOS=$(abs "$MACOS")
mkdir -p "$OUT" && OUT=$(cd "$OUT" && pwd)
BUILD=$ROOT/build
rm -rf "$BUILD/stage" && mkdir -p "$BUILD/stage" "$OUT"
if [ -z "$LINUX" ]; then
  "$ROOT/native/build.sh" "$BUILD/native/linux-x86_64" >/dev/null
  LINUX=$BUILD/native/linux-x86_64/libbotsqlite3.a
fi
cp -r "$ROOT/sqlite" "$BUILD/stage/sqlite"
STAGE=$BUILD/stage/sqlite
# every SQLite C function the bindings declare must be exported by each archive
SYMS=()
for s in $(grep -oE '^private extern c fn sqlite3_[a-z0-9_]+' "$STAGE/sqlite.bot" | awk '{print $5}' | sort -u); do SYMS+=(-symbol "$s"); done
(cd "$STAGE" && {
  "$BOT" native add "$LINUX" -target linux-x86_64 -name botsqlite3 -license blessing -notice NOTICE-SQLITE.txt "${SYMS[@]}" >/dev/null
  "$BOT" native require m -target linux-x86_64 -origin system >/dev/null
  if [ -n "$MACOS" ]; then
    # No -symbol checks here: the package manager's archive reader cannot read Apple ar's __.SYMDEF SORTED index
    # (it reports 0 names), so it cannot verify a Mach-O archive's exports. The macOS link in CI is the check.
    "$BOT" native add "$MACOS" -target macos-aarch64 -name botsqlite3 -license blessing -notice NOTICE-SQLITE.txt >/dev/null
    "$BOT" native require m -target macos-aarch64 -origin system >/dev/null
  fi
  "$BOT" native audit . | tail -20
})
rm -rf "$BUILD/pack-a" "$BUILD/pack-b" && mkdir -p "$BUILD/pack-a" "$BUILD/pack-b"
"$BOT" package pack "$STAGE" -out "$BUILD/pack-a" >"$BUILD/pack-a.log"; head -3 "$BUILD/pack-a.log"
"$BOT" package pack "$STAGE" -out "$BUILD/pack-b" >/dev/null
cmp "$BUILD"/pack-a/*.botpkg "$BUILD"/pack-b/*.botpkg
cp "$BUILD"/pack-a/*.botpkg "$OUT/"
if command -v sha256sum >/dev/null; then sha256sum "$OUT"/*.botpkg; else shasum -a 256 "$OUT"/*.botpkg; fi
