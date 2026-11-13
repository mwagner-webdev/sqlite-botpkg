#!/bin/sh
# Fetch sqlite.org's own prebuilt `sqlite3` command-line shell (3.54.1) as an independent oracle, and verify its SHA3-256 against the value
# sqlite.org publishes (https://www.sqlite.org/download.html). The oracle is *not* built from our amalgamation compile.
#   scripts/fetch_oracle.sh OUTDIR     -> OUTDIR/sqlite3
set -eu
out=${1:?usage: fetch_oracle.sh OUTDIR}
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) name=sqlite-tools-linux-x64-3540100.zip; sha3=555635de98534d87a67ee2e6e1b0d79f494b1b33b223477d3e7a8ea0c66e416f;;
  Darwin-arm64) name=sqlite-tools-osx-arm64-3540100.zip; sha3=a3106c6db3b50ec9ef4fde4edfafe7504179e9bfd7e0816a280b29c4d56a2e7b;;
  *) echo "no pinned sqlite3 CLI for $(uname -s)-$(uname -m)" >&2; exit 1;;
esac
mkdir -p "$out"
curl -fsSL "https://www.sqlite.org/2026/$name" -o "$out/$name"
got=$(python3 -c 'import hashlib,sys;print(hashlib.sha3_256(open(sys.argv[1],"rb").read()).hexdigest())' "$out/$name")
[ "$got" = "$sha3" ] || { echo "SHA3-256 mismatch for $name: $got" >&2; exit 1; }
python3 -c 'import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$out/$name" "$out"
chmod +x "$out/sqlite3"
"$out/sqlite3" --version
