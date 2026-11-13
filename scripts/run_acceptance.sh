#!/bin/bash
# The portable acceptance suite, as a consumer runs it: a fresh project, the package installed from a .botpkg,
# every program compiled to a native executable (AOT, no JIT, no -L flags) and run.
#
#   BOT=/path/to/botlish scripts/run_acceptance.sh PACKAGE.botpkg [WORKDIR]
#
# Needs the oracle binary at build/oracle/sqlite3 (scripts/fetch_oracle.sh build/oracle) for the interop step.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOT=${BOT:-$ROOT/botlish}
PKG=$(cd "$(dirname "${1:?usage: run_acceptance.sh PACKAGE.botpkg [WORKDIR]}")" && pwd)/$(basename "$1")
W=${2:-$ROOT/build/consumer-run}
ORACLE=${ORACLE:-$ROOT/build/oracle/sqlite3}
rm -rf "$W" && mkdir -p "$W"
cp "$ROOT"/consumer/*.bot "$W"/ && cp -r "$ROOT/consumer/apps" "$W/apps"
cd "$W"
echo "== platform: $(uname -srm)"
"$BOT" -version | sed 's/^/== compiler: /' | head -4
printf '{\n  "schema": 1,\n  "name": "sqlite_acceptance",\n  "version": "0.1.0"\n}\n' > botlish.json
"$BOT" add "$PKG" || { echo "FAIL install"; exit 1; }
"$BOT" verify || { echo "FAIL verify"; exit 1; }
"$BOT" native plan | sed 's/^/== native plan: /' | head -12
status=0
build() {  # NAME
  if ! "$BOT" -warnings error -emit-native-executable "$1.bot" > "$1.build.log" 2>&1; then echo "FAIL build $1"; cat "$1.build.log"; status=1; return 1; fi
}
echo "== build"
for p in info ac_basic ac_values ac_persistence ac_errors ac_transactions ac_resources ac_contention ac_composition interop_write interop_read tasklist kv; do
  build $p && echo "built $p"
done
echo "== info"
./info
echo "== acceptance programs"
total_pass=0
for p in ac_basic ac_values ac_persistence ac_errors ac_transactions ac_resources ac_contention ac_composition; do
  [ -x ./$p ] || { echo "FAIL $p: not built"; status=1; continue; }
  ./$p > "$p.log" 2>&1; rc=$?
  line=$(grep '^RESULT ' "$p.log" | tail -1)
  grep -v '^PASS' "$p.log" | grep -v '^RESULT' | sed "s/^/  [$p] /"
  if [ $rc -ne 0 ] || ! echo "$line" | grep -q 'failed=0$'; then echo "FAIL $p (exit $rc): ${line:-no RESULT line}"; status=1; else echo "PASS $p: $line"; fi
  n=$(echo "$line" | sed -n 's/.*passed=\([0-9]*\).*/\1/p'); total_pass=$((total_pass + ${n:-0}))
done
echo "== independent oracle (sqlite.org's own sqlite3 shell)"
if [ -x "$ORACLE" ]; then
  "$ROOT/scripts/oracle.sh" "$W" "$ORACLE" > oracle.log 2>&1; rc=$?
  grep -v '^PASS' oracle.log
  if [ $rc -ne 0 ]; then echo "FAIL oracle"; status=1; else echo "PASS oracle: $(grep -c '^PASS' oracle.log) checks"; fi
else echo "FAIL oracle: $ORACLE missing"; status=1; fi
echo "== applications across processes"
rm -f app.db kv.db
out=$(./tasklist app.db add "write the report"; ./tasklist app.db add "ship it"; ./tasklist app.db done 1; ./tasklist app.db list; ./tasklist app.db pending; ./tasklist app.db finish; ./tasklist app.db pending; ./tasklist app.db rm 2; ./tasklist app.db list)
expected=$'added 1\nadded 2\ndone\n[x] 1  write the report\n[ ] 2  ship it\n[ ] 2  ship it\nfinished 1\n[x] 1  write the report'
exp2=$'added 1\nadded 2\ndone\n[x] 1  write the report\n[ ] 2  ship it\n[ ] 2  ship it\nfinished 1\nremoved\n[x] 1  write the report'
if [ "$out" = "$exp2" ]; then echo "PASS tasklist: persistence across 9 processes"; else echo "FAIL tasklist"; echo "$out"; status=1; fi
./tasklist app.db done nonsense > /dev/null; if [ $? -eq 1 ]; then echo "PASS tasklist: bad input exits 1"; else echo "FAIL tasklist exit status"; status=1; fi
out=$(./kv kv.db set greeting "hello ✓"; ./kv kv.db get greeting; ./kv kv.db set other 2; ./kv kv.db keys; ./kv kv.db del other; ./kv kv.db keys)
if [ "$out" = $'ok\nhello ✓\nok\ngreeting\nother\ndeleted\ngreeting' ]; then echo "PASS kv: persistence across 6 processes"; else echo "FAIL kv"; echo "$out"; status=1; fi

rm -f app.db kv.db *.db *-journal
echo "== summary: $total_pass checks in the acceptance programs"
if [ $status -eq 0 ]; then echo "ACCEPTANCE OK"; else echo "ACCEPTANCE FAILED"; fi
exit $status
