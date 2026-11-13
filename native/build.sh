#!/bin/sh
# Build the pinned upstream SQLite amalgamation into a static archive for the host.
#   native/build.sh OUTDIR      -> OUTDIR/libbotsqlite3.a  (+ OUTDIR/sqlite3.h)
# Inputs are verified, nothing is downloaded: native/vendor/sqlite-amalgamation-3540100.zip is committed
# and its SHA3-256 is the one sqlite.org publishes (https://www.sqlite.org/download.html).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: build.sh OUTDIR}
zip=$here/vendor/sqlite-amalgamation-3540100.zip
want_sha3=92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30
got=$(python3 -c 'import hashlib,sys;print(hashlib.sha3_256(open(sys.argv[1],"rb").read()).hexdigest())' "$zip")
[ "$got" = "$want_sha3" ] || { echo "amalgamation SHA3-256 mismatch: $got" >&2; exit 1; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
python3 -c 'import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$work"
src=$work/sqlite-amalgamation-3540100
mkdir -p "$out"
CC=${CC:-cc}
# Flags: see native/FLAGS.md
$CC -O2 -fPIC -c "$src/sqlite3.c" -o "$work/sqlite3.o" \
  -DSQLITE_THREADSAFE=1 -DSQLITE_DQS=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_SHARED_CACHE \
  -DSQLITE_OMIT_DEPRECATED -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
  -DSQLITE_USE_URI=0
rm -f "$out/libbotsqlite3.a"
ar rcs "$out/libbotsqlite3.a" "$work/sqlite3.o"
cp "$src/sqlite3.h" "$out/sqlite3.h"
echo "built $out/libbotsqlite3.a"
