#!/bin/bash
# Run the already-built acceptance executables of a run_acceptance.sh work directory under valgrind memcheck.
#   scripts/valgrind.sh WORKDIR [LOGDIR]
# Reports invalid reads/writes, uses of uninitialised values and leaks at the C boundary. The one expected finding is
# the Engine's 24-byte scratch slot (sqlite3_malloc64(16)), owned by the installed context, which Botlish never
# releases at program end (concept.resources: "nothing is released at the program's end").
set -uo pipefail
W=${1:?usage: valgrind.sh WORKDIR [LOGDIR]}
L=${2:-$W/valgrind}
mkdir -p "$L"; cd "$W"
rc=0
for p in ac_basic ac_values ac_persistence ac_errors ac_transactions ac_resources ac_contention ac_composition interop_write; do
  [ -x ./$p ] || continue
  valgrind --error-exitcode=9 --leak-check=full --show-leak-kinds=definite,indirect,possible --errors-for-leak-kinds=none \
    --log-file="$L/$p.vg" ./$p > "$L/$p.out" 2>&1
  r=$?
  errs=$(grep -c -E "Invalid (read|write)|uninitialised|Mismatched free|Invalid free" "$L/$p.vg" || true)
  lost=$(grep -E "definitely lost:" "$L/$p.vg" | head -1 | sed 's/.*definitely lost: //; s/ in.*//')
  echo "$p: valgrind memory errors=$errs, definitely lost=${lost:-0} bytes, program exit=$r, $(grep '^RESULT' "$L/$p.out" | tail -1)"
  [ "$errs" = 0 ] || rc=1
done
rm -f *.db *-journal
exit $rc
