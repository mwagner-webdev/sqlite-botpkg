#!/bin/bash
# Independent oracle: sqlite.org's own `sqlite3` shell against files the Botlish package wrote and wrote for.
#   scripts/oracle.sh WORKDIR SQLITE3
# WORKDIR holds the built consumer executables (interop_write, interop_read). Exits non-zero on any difference.
set -euo pipefail
W=${1:?usage: oracle.sh WORKDIR SQLITE3}
S=${2:?usage: oracle.sh WORKDIR SQLITE3}
cd "$W"
fail=0
check() {  # NAME EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then echo "PASS oracle: $1"; else echo "FAIL oracle: $1"; echo "  expected: $2"; echo "  actual:   $3"; fail=1; fi
}
echo "oracle: $("$S" --version | cut -c1-40)"
rm -f interop.db interop.db-journal cli.db cli.db-journal
./interop_write

# --- direction 1: a file written by the Botlish package, read by sqlite.org's shell --------------------------------
check "integrity_check" "ok" "$("$S" interop.db 'pragma integrity_check')"
check "header user_version" "54" "$("$S" interop.db 'pragma user_version')"
check "page_size and journal mode are SQLite's defaults" "4096|delete" "$("$S" interop.db 'select (select page_size from pragma_page_size), (select journal_mode from pragma_journal_mode)')"
check "storage classes" "1|null|2|integer|3|integer|4|integer|5|real|6|real|7|real|8|text|9|text|10|text|11|blob|12|blob|13|real" \
  "$("$S" -separator '|' interop.db "select group_concat(id || '|' || typeof(x), '|') from (select id, x from v order by id)")"
check "int64 bounds" "9223372036854775807|-9223372036854775808" "$("$S" -separator '|' interop.db 'select quote(x), quote((select x from v where id = 3)) from v where id = 2')"
check "reals are bit-exact" "1|1|1|1" "$("$S" -separator '|' interop.db 'select (select x = 0.1 from v where id = 5), (select x = 1.7976931348623157e308 from v where id = 6), (select x = 5e-324 from v where id = 7), (select x = -2.5 from v where id = 13)')"
check "NULL is NULL, not ''" "1|0|0" "$("$S" -separator '|' interop.db "select (select x is null from v where id = 1), (select x is null from v where id = 10), (select x is null from v where id = 12)")"
check "unicode text, length in characters and bytes" "héllo ✓ 日本語 🎉|13|25" "$("$S" -separator '|' interop.db "select x, length(x), length(cast(x as blob)) from v where id = 8")"
check "text with an embedded NUL" "610062|3" "$("$S" -separator '|' interop.db "select hex(x), length(cast(x as blob)) from v where id = 9")"
check "empty text and empty blob" "text|0|blob|0" "$("$S" -separator '|' interop.db "select typeof(a.x), length(a.x), typeof(b.x), length(b.x) from v a, v b where a.id = 10 and b.id = 12")"
check "blob 0..255" "256|000102030405060708090A0B0C0D0E0F|FEFF" "$("$S" -separator '|' interop.db "select length(x), substr(hex(x), 1, 32), substr(hex(x), 509, 4) from v where id = 11")"
check "committed transaction persisted, failed one did not" "1,2" "$("$S" interop.db "select group_concat(n, ',') from (select n from tx order by n)")"
check "row count" "13" "$("$S" interop.db 'select count(*) from v')"

# --- the shell writes, the Botlish package reads ----------------------------------------------------------------------
"$S" cli.db <<'SQL'
create table w(id integer primary key, label text, x);
insert into w values (1, 'null', NULL);
insert into w values (2, 'int-max', 9223372036854775807);
insert into w values (3, 'int-min', -9223372036854775808);
insert into w values (4, 'real', 0.1);
insert into w values (5, 'unicode', 'héllo ✓ 日本語 🎉');
insert into w values (6, 'blob', x'00FF10AB');
insert into w values (7, 'empty-text', '');
insert into w values (8, 'real-max', 1.7976931348623157e308);
pragma user_version = 77;
SQL
if ./interop_read | tee interop_read.log | grep -v '^PASS'; then :; fi
grep -q '^RESULT passed=[0-9]* failed=0$' interop_read.log || { echo "FAIL oracle: interop_read"; fail=1; }
grep '^PASS' interop_read.log | sed 's/^PASS /PASS oracle (shell wrote, Botlish read): /'

# --- the Botlish package appends to a file the shell created, the shell sees it -----------------------------------------
check "integrity after both wrote" "ok" "$("$S" cli.db 'pragma integrity_check')"
if [ $fail -ne 0 ]; then echo "RESULT oracle failed"; exit 1; fi
echo "RESULT oracle ok"
