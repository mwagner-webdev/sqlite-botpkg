# SQLITE-BOTPKG-CLEANROOM-MILESTONE-1

A portable Botlish package for the original SQLite engine, verified on Linux and macOS.

Evidence labels: **[inspection]** read from source/reference · **[executed]** run in the Linux clean-room · **[CI]** run by GitHub Actions (run URL + commit) · **[projected]** not run.
Companion documents: `SQLITE-BOTPKG-CAPABILITY-CENSUS.md`, `SQLITE-BOTPKG-LANGUAGE-FINDINGS.md`, `sqlite/README.md`. Logs and probes: `audit/sqlite-botpkg/`.

## 1. Executive result and completion status

**Status: complete.** All completion criteria in §18 are met, including the macOS one, with the evidence below. Stated plainly:

* A distributable **`sqlite-0.1.0.botpkg`** exists (Linux x86-64 + macOS arm64 in one artifact, SHA-256 `2784bbcf738bc180d783d7be2045cd5d0ca8bc12f99538cee551377e9ddc1ba7`, built by CI, packed deterministically) over the **unmodified upstream SQLite 3.54.1** amalgamation (SHA3-256 verified against sqlite.org). **[CI]**
* The **same consumer source** (13 programs, 257 acceptance checks + 25 oracle checks + 3 application checks, built with `-warnings error` as native executables) passes on
  **Linux x86-64** (Ubuntu 24.04, kernel 7.0.0-1017-azure) **and macOS arm64** (`macos-15`, macOS 15.8.2 24H232, Darwin 24.6.0, **real arm64, not Rosetta**, Apple clang 17.0.0, Xcode 16.4, SDK 15.5), by native AOT — no JIT, no `-backend cranelift`, no OS conditional in any `.bot` file. **[CI]**
* **macOS evidence: GitHub Actions run https://github.com/mwagner-webdev/sqlite-botpkg/actions/runs/43608099240, commit `e5c6c03812426f87956735f6dc4570dfe5933aa9`, job "acceptance suite (macOS arm64, native AOT)" = success** (all 5 jobs of the run succeeded). The same macOS job passed earlier in run 43507081774 (commit `37b32100b422068046c17a7606d58d55cc68493a`, job 132167433717) before a CI-only fix (an `apt-get update` missing on the *Linux* valgrind step); the package and tests are unchanged between the two commits.
* The Botlish compiler used on macOS was **built from source in the same job** from upstream commit `cdb751b0…` (no JIT) — no macOS binary was trusted.
* Independent oracle: sqlite.org's own `sqlite3` 3.54.1 shell reads what the package wrote and the package reads what the shell wrote, on both OSs. **[CI]**
* valgrind over the 9 acceptance executables on Linux: 0 memory errors, no leak but the Engine's own 24-byte slot. **[CI]** and **[executed]**. It found a real one-byte over-read in an early version of the package, since fixed.
* **No Botlish compiler/runtime change was needed or made.** The ledger (`SQLITE-BOTPKG-LANGUAGE-FINDINGS.md`) records 23 findings, none a hard blocker. The decisive one: **resources cannot be borrowed (F-04)**, so `Connection`/`Statement` are generation-checked *handles* owned by an `Engine` context rather than affine resources — memory-safe and leak-countable, but "use after close" is detected at run time, not excluded statically. Only `Transaction` is a real resource.
* **Not claimed:** macOS x86-64 (Botlish's native backend is arm64-only on macOS); ASan/UBSan (not run); static exclusion of use-after-close; SQL math functions (deliberately not compiled in, F-25); valgrind on macOS.

## 2. Clean-room environment and Botlish revision

| | |
|---|---|
| Repository | https://github.com/mwagner-webdev/sqlite-botpkg (public) — package, native build, consumer project, scripts, CI; no copy of any other SQLite wrapper was used (the SQLite C API and its documentation were the references) |
| Linux host **[executed]** | Ubuntu 24.04.3 on WSL2 (kernel 6.6.87.2), x86-64, Intel Xeon E-2176G, 12 threads, 16 GB; gcc 13.3.0, GNU ld 2.42, valgrind 3.22.0 (`logs/environment-linux.log`) |
| Botlish compiler | `botlish` single-file build, **source revision cdb751b**, front end `18f05c733c33599f-5527019`, Tcl 9.0.1, native backend `ca1074e8-…`; SHA-256 `e16550bc50da47d457284ccfb40869f9eb5ef2c56592b6b6eaf8ec27f86a3fba` — identical to the published `single-latest` asset **[executed]** |
| macOS compiler | built in CI from the same upstream commit `cdb751b0ca6171b2a1bcf46a09907316a6a6cb05` (`single/macos/build.sh` → `Botlish.app`, no JIT) **[CI]** |
| SQLite | **3.54.1**, source id `2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76`; amalgamation `sqlite-amalgamation-3540100.zip`, SHA3-256 `92281c86…df28e30` (verified by `native/build.sh`) |
| Compiler/runtime changes | **none.** Botlish was used as shipped; every limitation is worked around in the package or recorded in the findings ledger |

## 3. Initial capability census

Full text: `SQLITE-BOTPKG-CAPABILITY-CENSUS.md`. What mattered:

* ✔ `private extern c fn`, per-target bundled static archives, `.bot_modules/.targets` views linked without `-L`, deterministic `package pack`; one `extern c library` declaration serves both OSs.
* ✔ Byte borrowing (`read/write noescape`) with write-back; native views for out-pointers; libc `memcpy`/`strlen` for dynamic-length reads; C scalars as proven integer domains.
* ✔ Resources with lexical cleanup (also on `fail`); context-owned affine state observed in place; contexts as an airlock for raw authority.
* ✖ **Resources cannot be borrowed** (F-04); no Option/payload enums (F-03); no NULL function pointer (F-05); no portable stdout/exit (F-01/F-02); unbounded `int` context fields fail native lowering (F-08).

## 4. Native SQLite dependency and linkage design

**Chosen: a pinned upstream amalgamation, compiled once per target into a static archive that the package bundles.** System SQLite was rejected: no `libsqlite3-dev` is installable here without root, versions differ per OS (macOS ships its own), and stable version reporting was a requirement.

* Source: `native/vendor/sqlite-amalgamation-3540100.zip`, committed; `native/build.sh` refuses any file whose SHA3-256 is not the one sqlite.org publishes. Nothing is downloaded at build time. **[executed]**
* Flags (`native/FLAGS.md`): `-O2 -fPIC`, `SQLITE_THREADSAFE=1`, `SQLITE_DQS=0`, `OMIT_LOAD_EXTENSION`, `OMIT_SHARED_CACHE`, `OMIT_DEPRECATED`, `DEFAULT_MEMSTATUS=0`, `LIKE_DOESNT_MATCH_BLOBS`, `USE_URI=0` (SQL math functions deliberately **not** enabled: see F-25). Compiler: host `cc` (GCC 13.3 / Apple clang).
* Linking: `extern c library "botsqlite3"` in `sqlite.bot`; the package carries `targets/linux-x86_64/native/libbotsqlite3.a` and `targets/macos-aarch64/native/libbotsqlite3.a`, and **no system library**; the installed target view is linked without `-L`. A consumer needs only the host C driver. **[executed]** (Linux) **[CI]** (both).
* Reproducibility: the Linux archive built by CI (`ubuntu-24.04`, gcc 13.3) is **bit-identical** to the one built on the development host: SHA-256 `83fac6281928aa8c2c62ebe6ff139285ae8586c55510e25ca199453392a6ce7f` **[CI]** run 43608099240 vs **[executed]** (also identical, as `8add430d…`, before the math functions were dropped, run 43470724971). The macOS archive (`d2697dc2bf52ba3e1b6e553e1b983262ac04d437c8659f884f9723fa1f91b78a`) is Apple clang's own output on the runner.
* Only documented API is used (`sqlite3_open_v2`, `prepare_v2`, `step`, `bind_*64`, `column_*`, `changes64`, `exec`, …); no private symbols.
* Version at run time: `sqlite::version()`, `version_number()`, `source_id()`, `thread_mode()` (`consumer/info.bot` prints them).
* Maintenance: a new SQLite means a new vendored zip + SHA3 + package version; CI rebuilds and re-runs everything.
* Licence/notice: `NOTICE-SQLITE.txt` (public-domain blessing, source pin) is part of the package; `native add -license blessing` records it.

## 5. Public Botlish API and rationale

Three modules: `sqlite` (engine, connections, statements, transactions), `sqlite::value` (Value, Kind, Row), `sqlite::failure` (Failure, ErrorKind). Full tables in `sqlite/README.md`. Representative use (the real API; `consumer/apps/taskdb.bot`):

```botlish
fn add(db: sqlite::Connection, title: str) -> int errors sqlite::failure::Failure:
    db.execute("insert into tasks(title) values (?)", [sqlite::value::text(title)])
    db.last_insert_rowid()

fn of_row(r: sqlite::value::Row) -> Task errors sqlite::value::ColumnError:
    done = r.integer_at(2)
    Task {id: r.integer_at(0), title: r.text_at(1), done: done == 1}
```

Rationale: a small API built around what applications do — `open*`, `execute`, `query`, `query_one`, `prepare`/`run`/`rows`/`step`, `begin`/`commit` — rather than SQLite's handles. `execute`/`query` prepare, run and finalize on **every** path. Parameters are bound, never interpolated (the SQL text and parameters are separate arguments; `bind_all` requires exactly one value per parameter). No ORM, no query builder. Records of what is **fully implemented / partial / unsupported** are in §17.

## 6. Context and application composition

The desired architecture is implemented as stated:

* The **application chooses and owns** its connections: `db = sqlite::open(path)` … `db.close()`; there is no global connection.
* The **capability** is the `sqlite::Engine` context, installed once at startup (`with context sqlite::engine()`).
* Library code declares nothing: the compiler derives that a function calling `db.execute` requires the Engine (`botlish -contexts`: `contextparam … sqlite::Engine`; `-direct`: `module sqlite: contextualized … mediated by sqlite::Engine`, `logs/contexts.log`), so the same functions run under a CLI, a test runner or a server. **[executed]**
* Two independent consumers of one package API: `consumer/apps/taskdb.bot` and `apps/kvstore.bot` share no code; `tasklist.bot` and `kv.bot` are two programs over them; `ac_composition.bot` drives both on **one** connection and on **separate** connections (12 checks). **[executed]**
* The Engine is an *airlock*: the package module stays "ordinary" for its consumers although it makes retaining C calls, because every such call is inside a function requiring the Engine.
* No convenience layer hides a connection: an explicit connection is always passed; the context carries the native tables, not "the current database".

## 7. Resource ownership and cleanup behaviour

| situation | behaviour | test **[executed]** |
|---|---|---|
| Connection ownership | the Engine owns each `sqlite3*`; `Connection` is a copyable handle `{engine, slot, generation}` | `ac_basic`, `ac_persistence` |
| double close / use after close | `misuse` Failure; the stale handle is never dereferenced | `ac_errors: handle_misuse`, `ac_persistence: repeated` |
| slot reuse | a new object in a reused slot has a new generation; old handles do not alias it | `ac_resources: close live` |
| close with live statements | `close` finalizes them first; their handles become invalid; `open_statements()` returns to 0 | `ac_resources` |
| statement finalization / errors in `step` | a failed `step` resets the statement; `execute`/`query` finalize on every path | `ac_errors` (open_statements()==0 after every failure) |
| early termination of iteration | `reset()` rewinds; `finalize()`/`close()` release; a write while a read is open works | `ac_resources: early exit` |
| prepared-statement reuse | 2000 runs on one statement, 500 one-shot queries: no growth | `ac_resources: no growth` |
| ownership of bound values | TEXT/BLOB are copied into Engine-owned `sqlite3_malloc64` buffers, bound `SQLITE_STATIC`, freed on `reset`/`finalize`/`close`; rebinding is covered | `ac_resources: bound values`, valgrind |
| values from SQLite-owned memory | copied out immediately (`memcpy` into `Bytes`); they outlive the statement, the delete and the close | `ac_resources: values outlive` |
| repeated open/close | 300 cycles on a file, 2000 in memory: no stale handle, no leak | `ac_persistence`, `bench` |
| failed open | the handle SQLite allocated is closed; `open_connections()` unchanged | `ac_persistence: open failures` |
| scope exit of a Transaction | cleanup rolls back (also on `fail`) | `ac_transactions` |

**Honest limit (F-04):** `Connection`/`Statement` are *values*, so "use after close is impossible" is *detected*, not statically excluded. Only `Transaction` is an affine resource. Botlish releases nothing at program end, so an application must `close` what it opens; the counters make a leak assertable, and valgrind reports exactly one lost block — the Engine's own 24-byte scratch slot.

## 8. Values, NULL semantics and FFI memory lifetimes

| storage class | Botlish | notes (all **[executed]**, `ac_values`, cross-checked with SQLite's own `typeof/length/hex`) |
|---|---|---|
| NULL | `Value` with `Kind::Null` | never `""`, empty blob or 0: stored as `null/text/blob/integer/real` respectively; `Value ==` separates them |
| INTEGER | `Int64` (an `Int in −2^63..2^63−1`) | max, min, 0, −1, 2^32 round-trip; SQLite-side overflow becomes REAL; `integer_of` refuses 2^63 |
| REAL | `Float64` | max double, smallest subnormal `5e-324`, smallest normal, `0.1` bit-exact (SQLite agrees `x = literal`); SQL `-0.0` reads as `0.0`; stored `+Inf` → Failure `encoding` (F-24) |
| TEXT | `str` | `héllo wörld`, CJK, astral-plane emoji, RTL; char vs byte lengths agree with SQLite; **embedded NUL** round-trips (`610062000063` stored); invalid UTF-8 in the database → `encoding` Failure |
| BLOB | `std::abi::bytes::Bytes` | all 256 byte values; **empty blob stays a BLOB** (`zeroblob(0)`; a NULL pointer would bind NULL) |

Lifetimes: SQLite returns pointers valid only until the next `step/reset/finalize`; every read copies immediately into Botlish storage (`copy_out`). Bytes handed to SQLite are copied into a package-owned native buffer first, because a `Bytes` borrow lasts one C call only (F-05/F-06). valgrind over the 9 acceptance executables: **0** invalid reads/writes/uninitialised uses after the fix **[executed]** (it had found a real one-byte over-read in my `prepare` call before — `logs/valgrind-PREFIX-ac_resources.log`).

## 9. Transactions and error contracts

**Transactions** (`ac_transactions`, 28 checks **[executed]**): successful multi-statement commit; rollback after a failing second insert **by scope exit alone** (no explicit rollback — the cleanup did it); constraint failure inside a transaction; explicit `rollback()`; early `return` without commit; falling through to `commit()`; savepoints — inner rollback/outer commit, inner commit/outer rollback, inner failure with outer surviving; **failed commit** under a real reader lock: reported as `busy`, the level is rolled back, no transaction left open, the connection writes again. Implemented with real `BEGIN/COMMIT/ROLLBACK/SAVEPOINT/RELEASE/ROLLBACK TO`. No claim that arbitrary exceptions auto-roll-back: Botlish has none; the rollback is the **resource cleanup of the scope that owns the `Transaction`**.

**Errors.** One declared error `sqlite::failure::Failure {info: Info{kind, code, extended, message, operation}}`; `kind` is derived from SQLite's primary result code, never the message (`sqlite::failure::classify`). Distinguished: constraint (UNIQUE 2067, PRIMARY KEY 1555, NOT NULL 1299, CHECK 275, FOREIGN KEY 787 — all **[executed]** through `extended`), busy, locked, malformed SQL (`SqlError`, op `prepare`), `cant-open`, `read-only`, I/O/corrupt/full classes, and `misuse` (stale handle, wrong parameter count, empty SQL). Other errors: `NoRows`, `ColumnError`, `IntegerOutOfRange`. SQLite operational errors never panic the process. Documented behaviour: failed commit → rolled back + reported; failed cleanup → silent (cleanup cannot fail); partially executed statement → SQLite undoes it; the failing statement of a transaction leaves the transaction open.

## 10. Threading and concurrency restrictions

* Build mode: `SQLITE_THREADSAFE=1` (serialized); `thread_mode()` returns 1 **[executed]**.
* Model: **single owner**. Botlish threads are VMs that share nothing: each installs its own Engine; the package's Engine and handles are VM-local. **[executed]** two threads each opened their own in-memory database, inserted 3000 and 2000 rows concurrently and returned the right counts.
* A `Connection` cannot cross threads: sending one as a thread start value is the compile-time error `THREAD-ENTRY-SIGNATURE … not sendable … an identity of one VM: a slot, a handle` **[executed]** (`logs/threads.log`). The package therefore *can* restrict sharing, structurally.
* No callbacks, no thread-local state in the package. No claim is made that SQLite's serialization makes a shared handle safe.
* Lock contention (two connections, one file; `ac_contention`, 20 checks **[executed]**, deterministic): a writer holding `BEGIN IMMEDIATE` → the other connection's write fails at once with `Busy` (code 5), `begin_immediate` also `Busy`, reads still work, a 50 ms busy timeout still ends `Busy`; after commit/rollback/a failed holder's scope exit the other connection writes; `Locked` (code 6) from dropping a table a live statement reads.

## 11. Linux implementation and acceptance evidence

**[executed]** on the host in §2, from a fresh project that installs `dist/sqlite-0.1.0.botpkg` (`scripts/run_acceptance.sh`; log `audit/sqlite-botpkg/logs/acceptance-linux-local-with-CI-package.log` for the final CI-built package, **`ACCEPTANCE OK`**; the same suite also passed earlier on the pre-libm-removal package, `acceptance-linux-final.log`):

| program | checks |
|---|---|
| `ac_basic` (memory, schema, parameterised INSERT, SELECT, 100 rows, statement reuse) | 26 |
| `ac_values` (NULL, Unicode, BLOB, int64, REAL edges, ±Inf, accessors) | 63 |
| `ac_persistence` (reopen, commit/rollback persisted, read-only, open failures, 300 open/close) | 24 |
| `ac_errors` (5 constraint kinds with codes, invalid SQL, handle misuse) | 52 |
| `ac_transactions` (commit, scope-exit rollback, savepoints, failed commit) | 28 |
| `ac_resources` (early exit, close with live statements, outliving values, bound values, no growth) | 32 |
| `ac_contention` (busy, locked, lock release) | 20 |
| `ac_composition` (two consumers, shared and separate connections) | 12 |
| **programs total** | **257** |
| independent oracle (§13) | 25 |
| `tasklist` across 9 processes, bad input exit 1; `kv` across 6 processes | 3 |

Every program is built with **`-warnings error`** as a native executable (`-emit-native-executable`, AOT) with **no `-L`/`-I`**; each test controls its own database state (unique file, wiped first and last). Exact commands: `scripts/pack.sh`, `scripts/run_acceptance.sh`, `scripts/valgrind.sh`. Package sources: `sqlite.bot` 1170 lines (of which about 90 lines are the private C declarations), `value.bot` 192, `failure.bot` 128. Compile time ≈ 25 s per consumer program.

Case-to-evidence map of the milestone's acceptance table: in-memory `ac_basic`; file-backed persistence `ac_persistence`; schema creation `ac_basic`; parameterized INSERT `ac_basic`; SELECT / multiple rows `ac_basic`; NULL / Unicode / BLOB / large INTEGER `ac_values`; constraint error `ac_errors` (+ no leak); invalid SQL `ac_errors`; commit / rollback `ac_transactions`, `ac_persistence`; statement reuse `ac_basic`, `ac_resources`; early iteration exit `ac_resources`; two connections `ac_contention`; repeated open/close `ac_persistence`; package consumer: the whole `consumer/` project imports only the installed package.

## 12. macOS GitHub Actions configuration and executed evidence

Workflow: `.github/workflows/ci.yml` (triggered by any non-documentation push; documentation-only pushes are ignored). Jobs:

| job | runner | what |
|---|---|---|
| `native-linux` | ubuntu-24.04 | `native/build.sh` → `libbotsqlite3.a`; counts exported `sqlite3_*` symbols |
| `native-macos` | **macos-15 (arm64)** | same script with Apple clang → Mach-O arm64 archive |
| `package` | ubuntu-24.04 | pinned Linux compiler (SHA-256 checked) → `scripts/pack.sh` with **both** archives, packed twice and byte-compared → `sqlite-0.1.0.botpkg` |
| `linux-acceptance` | ubuntu-24.04 | fresh project, `botlish add` the artifact, `verify`, build every program natively, run everything, oracle, valgrind, benchmark (and the C benchmark) |
| `macos-acceptance` | **macos-15 (arm64)** | **builds the Botlish compiler from the pinned upstream commit** (`single/macos/build.sh` → `Botlish.app`), waits for this run's `package` artifact, then does exactly what the Linux job does (AOT only), plus `file`/`lipo`/`otool` of an executable and the benchmark |

The runner is recorded by the job itself and the job fails unless `uname -s` is Darwin, `uname -m` is arm64 and the process is not translated: `sw_vers` = macOS 15.8.2 (24H232); `Darwin 24.6.0 … RELEASE_ARM64_VMAPPLE arm64`; 3 CPUs, 7 GB; Xcode 16.4, SDK 15.5; `Apple clang version 17.0.0 (clang-1700.0.13.5)`; image `macos-15-arm64` 20261104.0514.

Steps' outcome in run 43608099240 (commit `e5c6c03…`), all **[CI]**:

1. *Obtain or build the specified toolchain* — the macOS compiler is built in-job from `mwagner-webdev/botlish@cdb751b0ca6171b2a1bcf46a09907316a6a6cb05` (its own `single/macos/build.sh` verifications pass: layout, arm64-only, signature ad hoc, **no JIT**); `botlish -version` prints `source revision: cdb751b, packaged` and `native JIT: unavailable (programs run natively as executables: -aot-run)`.
2. *Provision the declared SQLite dependency* — the pinned amalgamation is built by `native/build.sh` on the macOS runner (SHA3-256 verified) and bundled into the package.
3. *Build from a clean checkout* — `actions/checkout`; nothing cached but the toolchain build.
4. *Build an independent consumer* — a fresh project (`botlish add dist/sqlite-0.1.0.botpkg` → `view macos-aarch64: derived (9 files, 1 native library)`; `botlish verify`; `native plan`) compiles 13 programs with `-warnings error` to Mach-O executables.
5. *Execute the full portable suite* — `ac_basic` 26, `ac_values` 63, `ac_persistence` 24, `ac_errors` 52, `ac_transactions` 28, `ac_resources` 32, `ac_contention` 20, `ac_composition` 12 = **257**, `ACCEPTANCE OK`.
6. *File-backed persistence* — `ac_persistence`, `ac_transactions` (failed commit), `ac_contention`, `tasklist` across 9 processes, `kv` across 6.
7. *Rollback and prepared statements* — `ac_transactions`, `ac_basic`, `ac_resources`.
8. *Report version and platform* — the log prints `== platform: Darwin 24.6.0 arm64` and `sqlite version: 3.54.1`, number 3054001, source id `2026-10-16 14:45:20 555e07ef…ca76`, `threading mode: 1 (serialized)`.
9. *Fail on any failure* — the runner script exits non-zero on any failed build, program, `RESULT` line, oracle check or application check; a test that fails also `_exit(1)`s.

Independent oracle on macOS: sqlite.org's `sqlite-tools-osx-arm64-3540100.zip` (SHA3-256 `a3106c6d…2e7b` verified) — `PASS oracle: 25 checks`.

Logs: `audit/sqlite-botpkg/logs/ci-final/` (macOS and Linux acceptance logs, valgrind, benchmarks, `README.txt` with run/job ids). Also kept: the **first** macOS attempt (run 43497669917) which **failed** at `botlish add` — `system library m: verifying a system library on macos is not implemented (PM NATIVE)` — and led to F-25 and to building SQLite without its SQL math functions (`logs/ci-run-43497669917-macos-FAILED-install-system-libm.raw.log`). Notes the package manager prints on macOS: the bundled archive "carries no code signature … sign it when the application is signed" (static archive linked into the executable; the executables run unsigned-by-us on the runner) and "its install name is not @rpath-relative" (n/a for a static archive).

macOS x86-64: not available (the native backend and the compiler distribution are arm64-only on macOS), so it was neither claimed nor tested.

## 13. Independent SQLite interoperability checks

Oracle: **sqlite.org's own prebuilt `sqlite3` shell 3.54.1** (`sqlite-tools-linux-x64-3540100.zip`, SHA3-256 `555635de…e66f` verified by `scripts/fetch_oracle.sh`; macOS: `sqlite-tools-osx-arm64`, `a3106c6d…`), i.e. a build *independent* of our amalgamation compile. **[executed]** (`scripts/oracle.sh`, 11 + 12 + 2 checks):

* **Botlish writes, the shell reads** (`interop_write` → `interop.db`): `pragma integrity_check` = ok; `user_version` 54 (header field) ; default page size/journal mode; storage class of every row (`typeof`); int64 max/min via `quote`; REAL bit-exactness (`x = 0.1`, `1.7976931348623157e308`, `5e-324`, `-2.5`); NULL vs `''` vs `x''`; Unicode text with character and byte lengths (13/25); embedded NUL (`hex` = `610062`); empty text/blob typeof/length; blob 0..255 first/last bytes; committed transaction persisted (rows 1,2) and the failed one did not (no 99); row count.
* **The shell writes, Botlish reads** (`cli.db` → `interop_read`, 11 checks): NULL, int max/min, real, Unicode text, blob `00FF10AB`, empty text, `user_version` 77 written by the CLI, largest double.
* Integrity check after both wrote the same file.

## 14. Performance sanity measurements

Fixed workload, one run, **[executed]** Linux host of §2, native AOT executable (default Botlish native optimisation), SQLite = the shipped archive (`-O2`, `THREADSAFE=1`), wall clock via `gettimeofday`; same workload through the C API (`bench/bench.c`, `cc -O2`, linked against the same archive). `logs/bench-botlish-linux.log`, `logs/bench-c-linux.log`. Not an optimisation exercise.

| workload | Botlish (µs) | C (µs) | ratio |
|---|---:|---:|---:|
| open+close `:memory:` × 2000 | 5 074 | 2 428 | 2.1× |
| open+close file × 1000 | 22 325 | 19 811 | 1.1× |
| 20 000 prepared inserts in one transaction | 57 736 | 21 317 | 2.7× |
| same, 5 000 unprepared (`execute` each time) | 83 998 | 18 676 | 4.5× |
| read 20 000 rows as `List[Row]` (`query`) | 69 359 | 3 211 | 22× |
| read 20 000 rows with `step`/`row` | 43 410 | 2 557 | 17× |
| 20 000 autocommit inserts, `:memory:` | 48 704 | 17 428 | 2.8× |
| 300 autocommit inserts, file (one fsync each) | 3 374 351 | 3 454 918 | 1.0× (disk-bound: ≈ 11 ms per commit) |
| scale: insert 20k / 40k / 80k / 160k / 320k | 40 / 104 / 221 / 490 / 1 069 ms | — | ×2.1–2.6 per doubling |
| scale: read 20k / 40k / 80k / 160k / 320k | 62 / 85 / 205 / 427 / 861 ms | — | ×2.0–2.4 per doubling |

Reading: **no accidental quadratic behaviour** (growth ≈ ×2.1 per doubling after warm-up; the pure-Botlish collecting loop shows the same shape), **no per-row leak** (`open_statements()`/`open_connections()` are 0; valgrind clean), FFI overhead is **a few µs per row**. The reads are slower than C because each row builds a `Row` of independent copies (a `Bytes` + decoded `str` per TEXT column, a `List[Value]`) where the C loop merely touches SQLite's buffer and frees; the insert cost is the `List[Value]` construction, UTF-8 encoding and the copy into the engine-owned buffer. **Allocation:** SQLite's own allocations are its own (`sqlite3_malloc`); the wrapper adds, per bound TEXT/BLOB, one `sqlite3_malloc64` copy (freed at `reset`), and per read cell one Botlish-heap `Bytes` (then a `str`). No zero-allocation claim is made. 

**macOS arm64 (CI) and Linux x86-64 (CI), same program** (`logs/ci-final/`, µs; 3-CPU shared runners, so noisy): 

| workload | macOS arm64 | Linux CI (Botlish) | Linux CI (C) |
|---|---:|---:|---:|
| open+close `:memory:` ×2000 | 3 998 | 4 877 | 2 623 |
| open+close file ×1000 | 36 896 | 28 227 | 23 772 |
| 20 000 prepared inserts, one transaction | 30 364 | 45 153 | 10 165 |
| 5 000 unprepared inserts, one transaction | 36 130 | 62 054 | 9 147 |
| read 20 000 rows (`query`) | 32 123 | 64 002 | 2 884 |
| read 20 000 rows (`step`/`row`) | 28 171 | 43 914 | 2 836 |
| 20 000 autocommit inserts, `:memory:` | 39 795 | 54 571 | 18 146 |
| 300 autocommit inserts, file | 117 838 | 183 072 | 170 815 |
| scale insert 20k / 40k / 80k | 28.7 / 70.5 / 146.3 ms | 43.3 / 105.9 / 237.3 ms | 8.0 / 16.3 / 33.3 ms |
| scale read 20k / 40k / 80k | 24.3 / 54.6 / 108.8 ms | 31.3 / 67.3 / 165.5 ms | 2.8 / 5.6 / 11.3 ms |

The same shape on both OSs and on both runners: linear-ish growth, no leaks (`leaked connections=0 statements=0`), per-row cost a few microseconds.

## 15. Package installation and external consumer

* Package: `sqlite-0.1.0.botpkg` = `botlish.json` (schema 3, targets, libraries, license `blessing`), `sqlite.bot`, `sqlite/value.bot`, `sqlite/failure.bot`, `README.md`, `NOTICE-SQLITE.txt`, `targets/<T>/native/libbotsqlite3.a`. Packed twice, byte-identical **[executed]**. The CI-built artifact (`package` job, run 43608099240) has SHA-256 `2784bbcf738bc180d783d7be2045cd5d0ca8bc12f99538cee551377e9ddc1ba7`, 8 files: both archives (Linux `83fac628…a6ce7f`, macOS `d2697dc2…91b78a`). The Linux archive built in CI is bit-identical to the one built on the development host. The CI-built artifact was also installed **on the development host** and the whole suite re-run against it (`logs/acceptance-linux-local-with-CI-package.log`), so one artifact has now been consumed on three machines (Linux dev host, Linux runner, macOS runner). The GitHub runner for Linux also has the *system* SQLite 3.45.1 and its dev package installed (`dpkg -l`, `logs`), and the suite still reports `sqlite version: 3.54.1`: the bundled library, not the system one, is what runs.
* Install in a third-party project (what `run_acceptance.sh` does):
  ```sh
  printf '{"schema":1,"name":"myapp","version":"0.1.0"}' > botlish.json
  botlish add path/to/sqlite-0.1.0.botpkg   # recorded with its SHA-256; derives the target view
  botlish verify
  botlish -emit-native-executable myapp.bot
  ```
  `botlish native plan` prints what links from where (`libbotsqlite3.a` from `.bot_modules/.targets/<T>/sqlite/native/`, and nothing from the system but libc).
* The consumer project `consumer/` shares **no file** with `sqlite/`: it is copied into a clean directory and sees the package only through `.bot_modules`.
* Package documentation: `sqlite/README.md` (API, ownership, error contract, transaction semantics, threading, version policy, Linux/macOS setup).

## 16. Language and ecosystem findings

Details, reproducers and follow-ups in `SQLITE-BOTPKG-LANGUAGE-FINDINGS.md`. The ones that matter for the question "can Botlish already host a serious, stateful native library?":

1. **F-04 resources cannot be borrowed** — the shape-defining one: connections had to be context-owned handle values with generation checks instead of resources. Genuine language limitation; reproducible without SQLite.
2. **F-01/F-02 no portable stdout / exit status** — a single source file cannot print on Linux and macOS through `std::io`; tests use libc `write`/`_exit`.
3. **F-03 no Option / payload enums** — SQL NULL is an opaque tagged struct.
4. **F-05 no NULL function pointer** — `SQLITE_STATIC/TRANSIENT` unrepresentable; bound values are copied into Engine-owned buffers.
5. Minor: F-06, F-08, F-09, F-10, F-12, F-13, F-14, F-15, F-16 (Mach-O archive index), F-17/F-18 (macOS distribution), F-19, F-20, F-21, F-23, F-24, F-22.

No hard blocker. Nothing was patched in Botlish.

## 17. Known limitations and deferred features

| area | status |
|---|---|
| open (file, memory, read-only, existing), close, statements, binding, rows, NULL/INTEGER/REAL/TEXT/BLOB, transactions + savepoints, busy timeout, error contract, version reporting | **fully implemented** and tested |
| named parameters by name; `Statement` column-by-name streaming; trailing statements of a multi-statement SQL string in `prepare` (silently ignored — documented; `execute_script` for scripts) | **partial** (positional binding only; `?NNN`/`:name` work by position) |
| static "use after close is impossible" | **not achievable** with Botlish today (F-04): detected at run time |
| `REAL` ±Infinity | unrepresentable (F-24): a `Failure`, or read as TEXT |
| automatic release at program exit | not possible (language releases nothing): close what you open |
| ORM, virtual tables, custom functions, extensions, backup, encryption, replication, async, pooling, cross-thread sharing, incremental blob I/O, WAL tuning APIs, Windows, macOS x86-64 | **unsupported / out of scope** |
| sanitizers | valgrind memcheck executed on Linux; **ASan/UBSan were not run** (no instrumented Botlish runtime); macOS has no valgrind |
| macOS | arm64 only, AOT only (the compiler distribution has no JIT) |
| performance | not optimised; reads ≈ 17–22× the C loop's time because every row is copied into Botlish values |

## 18. Final acceptance matrix

| completion criterion | status | evidence |
|---|---|---|
| A distributable `botpkg` exists | **met** | `sqlite-0.1.0.botpkg`, SHA-256 `2784bbcf…1ba7`, CI `package` job; deterministic (packed twice, byte-identical) **[CI]** |
| It uses original SQLite 3 | **met** | unmodified 3.54.1 amalgamation, SHA3-256 verified; `sqlite::version()` = 3.54.1, source id `…555e07ef…ca76`, on both OSs, with a *different* system SQLite (3.45.1) installed on the Linux runner **[CI]** |
| A third-party consumer imports and executes it | **met** | fresh project, `botlish add`, only `.bot_modules`; 13 programs **[executed]** **[CI]** |
| Prepared statements and safe parameter binding | **met** | `ac_basic`, `ac_resources`; parameters always bound; count enforced **[CI]** |
| INTEGER, REAL, TEXT, BLOB, NULL behave correctly | **met** | `ac_values` 63 checks, cross-checked by SQLite's own `typeof/hex/length` and by the oracle **[CI]** |
| No known double-free / stale-handle defect | **met** (as detected, not statically excluded) | generation-checked handles, `ac_errors`/`ac_resources`/`ac_persistence`; valgrind 0 errors **[CI]**; **caveat F-04** |
| Transactions commit and roll back correctly | **met** | `ac_transactions` 28 checks incl. savepoints and failed commit **[CI]** |
| Persistent files survive close and reopen | **met** | `ac_persistence`, `tasklist` across processes **[CI]** |
| Independent SQLite interoperability checks pass | **met** | 25 oracle checks both directions, both OSs **[CI]** |
| Linux native tests execute successfully | **met** | dev host **[executed]**; Linux runner **[CI]**; CI-built package on the dev host **[executed]** |
| GitHub Actions executes the suite on macOS | **met** | run 43608099240, macOS job 132486984726 (and run 43507081774, job 132167433717) **[CI]** |
| macOS run URL and commit SHA recorded | **met** | https://github.com/mwagner-webdev/sqlite-botpkg/actions/runs/43608099240 — `e5c6c03812426f87956735f6dc4570dfe5933aa9` |
| Documented and independently installable | **met** | `sqlite/README.md`, this report, `native/FLAGS.md`; installable with `botlish add` on Linux and macOS **[CI]** |
| Language limitations reported, not hidden | **met** | `SQLITE-BOTPKG-LANGUAGE-FINDINGS.md`: 23 findings, 8 SQLite-free reproducers with captured output |
| No Botlish compiler/runtime changes | **met** | none made; compiler = upstream `cdb751b` (Linux binary SHA-256 pinned; macOS built from that commit) |

Section-by-section status of the brief's requirements:

| requirement | status |
|---|---|
| Capability census before design | done (`SQLITE-BOTPKG-CAPABILITY-CENSUS.md`) |
| Pinned reproducible native strategy; version reporting | done (§4) |
| Idiomatic API: connections, statements, values, queries | **fully implemented** within §17's bounds |
| Contexts and composition; two independent consumers | done (§6) |
| Transactions and error contract | done, savepoints included (§9) |
| Resource correctness (the listed scenarios) | done; limitation F-04 stated (§7) |
| Threading and concurrency boundaries; two-connection contention | done (§10) |
| Platform portability, no OS conditionals in `.bot` | done; costs recorded as F-01/F-02/F-25 |
| Acceptance programs and a representative application | done (`consumer/`, `tasklist`, `kv`) |
| Differential/independent verification; sanitizers | oracle done; valgrind done; **ASan/UBSan not run** |
| Performance sanity checks incl. C comparison | done (§14) |
| Package quality (metadata, docs, CI, private C declarations) | done |
| Defect ledger with SQLite-free reproducers | done |
| Evidence discipline | labels used throughout; logs in `audit/sqlite-botpkg/` |

## 19. Recommended next milestone

**A borrow/observe mode for resources, then re-host this package on it.** The single most valuable language feature this exercise points at is F-04: let a function *observe* an affine value without moving it (the compiler already tracks one owner; C calls and context element places already observe). With it, `Connection` and `Statement` become real resources (static "no use after close, no leak"), the generation table and the `Engine` slot machinery shrink, and every handle-style library benefits. Bounded scope: one language milestone (observe parameters + diagnostics), then `sqlite 0.2` replaces the tables, keeping the public call syntax (`db.execute(...)`) and the acceptance suite unchanged as the regression oracle. In parallel, two cheap wins from the ledger: a portable `std::io` installer (F-01) and `null_fn[...]`/`copy_from` FFI primitives (F-05/F-06).
