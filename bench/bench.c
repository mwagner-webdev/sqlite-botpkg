/* The same workload as consumer/bench.bot, straight through SQLite's C API (prepared statements, bound parameters,
 * the same table and rows, wall-clock microseconds). Built against the very archive the package ships:
 *   cc -O2 -o bench_c bench/bench.c -Ibuild/native/linux-x86_64 build/native/linux-x86_64/libbotsqlite3.a -lm -lpthread
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include "sqlite3.h"

static long now(void) { struct timeval tv; gettimeofday(&tv, 0); return tv.tv_sec * 1000000L + tv.tv_usec; }
static void report(const char *name, long n, long t0) { printf("bench %s: n=%ld total_us=%ld\n", name, n, now() - t0); }
static void check(int rc, sqlite3 *db) { if (rc != SQLITE_OK && rc != SQLITE_DONE && rc != SQLITE_ROW) { fprintf(stderr, "sqlite error %d: %s\n", rc, sqlite3_errmsg(db)); exit(1); } }

static sqlite3 *fresh(const char *path) {
  char j[256]; snprintf(j, sizeof j, "%s-journal", path); unlink(path); unlink(j);
  sqlite3 *db; check(sqlite3_open(path, &db), db);
  check(sqlite3_exec(db, "create table t(id integer primary key, a integer, b text, c real)", 0, 0, 0), db);
  return db;
}
static void insert(sqlite3 *db, long n, int batched, int prepared) {
  sqlite3_stmt *st = 0;
  if (batched) check(sqlite3_exec(db, "begin", 0, 0, 0), db);
  if (prepared) check(sqlite3_prepare_v2(db, "insert into t(a, b, c) values (?, ?, ?)", -1, &st, 0), db);
  for (long i = 0; i < n; i++) {
    char text[64]; int len = snprintf(text, sizeof text, "row number %ld", i);
    if (!prepared) check(sqlite3_prepare_v2(db, "insert into t(a, b, c) values (?, ?, ?)", -1, &st, 0), db);
    sqlite3_bind_int64(st, 1, i); sqlite3_bind_text(st, 2, text, len, SQLITE_TRANSIENT); sqlite3_bind_double(st, 3, 1.5);
    check(sqlite3_step(st), db);
    if (prepared) { sqlite3_reset(st); sqlite3_clear_bindings(st); } else sqlite3_finalize(st);
  }
  if (prepared) sqlite3_finalize(st);
  if (batched) check(sqlite3_exec(db, "commit", 0, 0, 0), db);
}
static long read_all(sqlite3 *db) {
  sqlite3_stmt *st; long n = 0;
  check(sqlite3_prepare_v2(db, "select a, b, c from t", -1, &st, 0), db);
  while (sqlite3_step(st) == SQLITE_ROW) {
    long a = sqlite3_column_int64(st, 0); const unsigned char *t = sqlite3_column_text(st, 1); int tl = sqlite3_column_bytes(st, 1); double c = sqlite3_column_double(st, 2);
    char *copy = malloc(tl + 1); memcpy(copy, t, tl); copy[tl] = 0; (void)a; (void)c; free(copy);   /* a copy out of SQLite's buffer, as the Botlish wrapper makes */
    n++;
  }
  sqlite3_finalize(st); return n;
}
static void scale(long n) {
  sqlite3 *db; check(sqlite3_open(":memory:", &db), db);
  check(sqlite3_exec(db, "create table t(id integer primary key, a integer, b text, c real)", 0, 0, 0), db);
  long t = now(); insert(db, n, 1, 1); report("scale_insert", n, t);
  t = now(); long got = read_all(db); report("scale_read", got, t);
  sqlite3_close(db);
}
int main(void) {
  long n = 20000, t;
  t = now(); for (int i = 0; i < 2000; i++) { sqlite3 *db; sqlite3_open(":memory:", &db); sqlite3_close(db); } report("open_close_memory", 2000, t);
  { sqlite3 *s; sqlite3_open("bench_oc.db", &s); sqlite3_close(s); }
  t = now(); for (int i = 0; i < 1000; i++) { sqlite3 *db; sqlite3_open("bench_oc.db", &db); sqlite3_close(db); } report("open_close_file", 1000, t);
  sqlite3 *db = fresh("bench_a.db");
  t = now(); insert(db, n, 1, 1); report("insert_batched_prepared", n, t);
  t = now(); long got = read_all(db); report("read_query_all", got, t);
  t = now(); got = read_all(db); report("read_step_row", got, t);
  sqlite3_close(db);
  db = fresh("bench_b.db"); t = now(); insert(db, 5000, 1, 0); report("insert_batched_unprepared", 5000, t); sqlite3_close(db);
  db = fresh("bench_c.db"); t = now(); insert(db, 300, 0, 1); report("insert_autocommit_file", 300, t); sqlite3_close(db);
  sqlite3 *mem; sqlite3_open(":memory:", &mem); sqlite3_exec(mem, "create table t(id integer primary key, a integer, b text, c real)", 0, 0, 0);
  t = now(); insert(mem, n, 0, 1); report("insert_autocommit_memory", n, t); sqlite3_close(mem);
  scale(20000); scale(40000); scale(80000);
  unlink("bench_oc.db");
  return 0;
}
