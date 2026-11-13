# sqlite 0.1.0 — the original SQLite 3 engine as a Botlish package

SQLite owns database semantics and storage. This package owns the boundary: a Botlish-typed, resource-safe
interface to the **unmodified upstream SQLite 3.54.1 amalgamation**, bundled as a static library for
Linux x86-64 and macOS arm64. Applications own their database connections and inject them where needed.

```botlish
import sqlite
import sqlite::failure
import sqlite::value

fn demo() -> unit errors sqlite::failure::Failure:
    db = sqlite::open_memory()
    db.execute("create table tasks(id integer primary key, title text not null)", [])
    db.execute("insert into tasks(title) values (?)", [sqlite::value::text("write the docs")])
    rows = db.query("select id, title from tasks", [])
    # rows is a List[sqlite::value::Row]; row.integer_at(0), row.text_at(1), row.named("title") ...
    db.close()

with context sqlite::engine()        # once, at program start: the application installs the capability
demo():
    on sqlite::failure::Failure f:
        unit                          # f.info.kind, f.info.code, f.info.extended, f.info.message
```

## Install

```sh
botlish add path/to/sqlite-0.1.0.botpkg      # records the archive and its SHA-256 in botlish.json
botlish verify
botlish -emit-native-executable app.bot      # no -L, no -I: the bundled archive is linked from the target view
```

* **Native only.** A program that calls C runs on the native backends: build an executable
  (`-emit-native-executable`, the only way on macOS, whose compiler distribution has no JIT) or use
  `-backend cranelift` on Linux. The Tcl backends (`interp`, `compile`) refuse the first C call (`NATIVE-ONLY`).
* **Linux x86-64**: needs `cc` (gcc) for the link and `libm` (glibc, libc6-dev). **macOS arm64**: Xcode command-line tools.
  macOS x86-64 is not supported by Botlish's native backend.
* The SQLite library is bundled (`targets/linux-x86_64/native/libbotsqlite3.a`, `targets/macos-aarch64/native/libbotsqlite3.a`); no
  system SQLite is used or required. `sqlite::version()` reports the version actually linked.

## The model: Engine context, handles, resources

| | what it is | who owns it |
|---|---|---|
| `sqlite::Engine` | a **context** the application installs once: `with context sqlite::engine()` | the program, for the program's life |
| `sqlite::Connection`, `sqlite::Statement` | small copyable **handles** (engine id, slot, generation) | nothing: the Engine owns the native `sqlite3*` / `sqlite3_stmt*` |
| `sqlite::Transaction` | an affine **resource** whose cleanup rolls back | the scope that called `begin()` |

* Library functions never mention the Engine: the compiler derives that a function calling `db.execute(...)` requires it, so
  the same functions run unchanged under a command-line program, a test, or a server that installed the Engine.
* There is no global connection. Each `open*` makes a connection you hold and `close`.
* A handle to a closed connection or finalized statement is **detected** (a `misuse` Failure), never dereferenced; a
  reused slot has a new generation, so an old handle cannot alias a new object; closing twice is a `misuse`, not a double free.
* `close(db)` finalizes the connection's live statements first (their handles become invalid), then `sqlite3_close_v2`.
* A `Connection` is not Sendable: the compiler rejects sending one to another thread (each thread is a VM with its own
  Engine). Single-owner model; see "Threading".
* The Engine and its handles live until the program ends; Botlish releases nothing at exit, so `close` what you open
  (`sqlite::open_connections()` / `open_statements()` count what is still open; the Engine's own 24-byte scratch slot is the
  only allocation valgrind reports as lost).

Why not Botlish resources for `Connection` and `Statement`? A resource passed to a function is *moved*, and Botlish has no
borrowing, so a resource-typed connection could serve one call. The Engine context is the language's mechanism for state that many
calls observe in place. See `SQLITE-BOTPKG-LANGUAGE-FINDINGS.md` F-04.

## API

Library identity: `sqlite::version()` ("3.54.1"), `version_number()` (3054001), `source_id()`, `thread_mode()` (1 = serialized).

Connections: `sqlite::open(path)`, `open_read_only(path)`, `open_existing(path)` (no create), `open_memory()`,
`db.open?()`, `db.close()`, `db.set_busy_timeout(ms)`, `db.last_insert_rowid()`, `db.in_transaction?()`.

Running SQL — every parameter is bound, never interpolated:

| call | returns |
|---|---|
| `db.execute(sql, params)` | rows the statement changed (0 for anything else); prepares, runs, finalizes on every path |
| `db.query(sql, params)` | `List[Row]` |
| `db.query_one(sql, params)` | the first `Row`, or fails `sqlite::NoRows` |
| `db.execute_script(sql)` | runs several statements, no parameters (`sqlite3_exec`) |
| `db.prepare(sql)` | a `Statement`; then `st.run(params)`, `st.rows(params)`, or `st.bind(i, v)` / `st.bind_all(vs)` + `st.step()` + `st.row()`; `st.reset()`, `st.finalize()` |

`params` must supply exactly one `Value` per parameter (`?`, `?NNN`, `:name` by position), else a `misuse` Failure. Only the
first statement of an SQL text is prepared; use `execute_script` for several.

`st.step()` is `true` while a row is available, `false` when done; stopping early is fine — `reset()` rewinds, `finalize()` releases,
`close()` releases everything. A failed `step` leaves the statement reset and reusable.

### Values (`sqlite::value`)

| SQLite | constructor | read |
|---|---|---|
| NULL | `value::null()` | `v.null?()`, `v.kind() == Kind::Null` |
| INTEGER | `value::integer(n)` (`n: Int64`), `value::integer_of(n)` (any Int, may fail `IntegerOutOfRange`) | `row.integer_at(i)` → `Int64` |
| REAL | `value::real(x)` (a finite `Float64`) | `row.real_at(i)` |
| TEXT | `value::text(s)` (UTF-8; NUL bytes allowed) | `row.text_at(i)` (non-UTF-8 text is a Failure of kind `encoding`) |
| BLOB | `value::blob(bytes)` (`std::abi::bytes::Bytes`; empty is still a BLOB) | `row.blob_at(i)` |

* NULL is a value of its own: never `""`, an empty blob, zero or a missing row. `Value` equality is structural per storage class.
* Typed readers fail with `ColumnError` (`WrongType`, `NoSuchColumn`, `NoSuchName`); `v.integer_or(default)` etc. substitute an explicit default.
* Access by index (`row.integer_at(0)`) or name (`row.named("title")`, the first column with that name).
* Values are independent copies: they stay valid after the statement is reset, finalized or the connection closed.
* `Float64` has no infinity: a stored `±Inf` REAL is reported as a Failure of kind `encoding` rather than clamped. `-0.0` reads as `0.0`.

### Failures (`sqlite::failure`)

Every operational SQLite failure is one declared error, `sqlite::failure::Failure`, with `f.info`:

| field | meaning |
|---|---|
| `kind` | stable `ErrorKind`: `Constraint`, `Busy`, `Locked`, `SqlError`, `Io`, `CantOpen`, `ReadOnly`, `Corrupt`, `Full`, `Misuse`, `Interrupted`, `Resource`, `Encoding`, `Other` — from SQLite's *primary result code* |
| `code`, `extended` | SQLite's primary and extended result codes (e.g. 19 / 2067 `SQLITE_CONSTRAINT_UNIQUE`) |
| `message` | SQLite's text, for people; never parse it |
| `operation` | `"open"`, `"prepare"`, `"bind"`, `"step"`, `"commit"`, ... |

`SqlError` covers `SQLITE_ERROR` (syntax errors, unknown tables/columns, ...). `Misuse` is also what the package reports for a
stale handle, a wrong parameter count or empty SQL. Nothing in this package panics on a SQLite error. Other errors:
`sqlite::NoRows`, `sqlite::value::ColumnError`, `sqlite::value::IntegerOutOfRange`.

### Transactions

```botlish
fn transfer(db: sqlite::Connection, from: sqlite::value::Int64, to: sqlite::value::Int64, cents: sqlite::value::Int64) -> unit errors sqlite::failure::Failure:
    tx = db.begin()                                # BEGIN (SAVEPOINT if one is already open)
    db.execute("update acct set cents = cents - ? where id = ?", [sqlite::value::integer(cents), sqlite::value::integer(from)])
    db.execute("update acct set cents = cents + ? where id = ?", [sqlite::value::integer(cents), sqlite::value::integer(to)])
    tx.commit()                                    # COMMIT
```

`Transaction` is a Botlish resource. If its scope ends without `commit()`/`rollback()` having consumed it — a `fail` out of the
second `execute`, a `return`, falling off the end — its cleanup rolls back. This is the language's cleanup model, not a callback
framework, and it is **not** an "exceptions roll back" claim: a `fail` rolls back because the scope that owns the `Transaction` ends.

* `begin()` inside an open transaction issues `SAVEPOINT botlish_spN`; each level commits (`RELEASE`) or rolls back (`ROLLBACK TO` + `RELEASE`) independently.
* `begin_immediate()` / `begin_exclusive()` take the write lock at the outermost level (a conflict is `busy` at `begin`).
* **Failed commit**: the package rolls that level back, so the connection is left with it closed, and reports the commit's Failure (e.g. `busy`).
* **Failed cleanup**: the implicit rollback cannot fail; if SQLite refuses it the connection stays as SQLite leaves it — check `db.in_transaction?()`.
* **Failed statement inside a transaction**: SQLite keeps the transaction open; the failing statement's own effects are undone. Use the scope's `fail` to roll everything back, or handle the Failure and continue.
* **Partially executed statement**: a multi-row statement that fails midway is atomic per statement in SQLite (its changes are undone).

### Locking and threads

Two connections to one file follow SQLite's locking: with the default busy timeout (0) a conflicting write fails at once with `Busy`;
`db.set_busy_timeout(ms)` waits up to `ms` first. `Locked` is contention inside one connection (e.g. dropping a table a live statement reads).

Threading mode: the bundled SQLite is compiled `SQLITE_THREADSAFE=1` (serialized). The package's own model is single-owner: Botlish threads are VMs that share nothing,
each installs its own Engine, and a `Connection` cannot be sent to another thread (compile-time error). Do not rely on SQLite's
serialization to share a database handle; open one connection per thread. There are no callbacks and no thread-local state.

## SQLite version policy

Pinned: the amalgamation `sqlite-amalgamation-3540100.zip` (SHA3-256 `92281c86…df28e30`, as published on sqlite.org/download.html),
compiled with the options in `native/FLAGS.md` of the source repository. Minimum supported version for a replacement archive: the
symbols the package declares (`sqlite3_prepare_v2`, `sqlite3_bind_*64`, `sqlite3_changes64`, `sqlite3_total_changes64`, ... all in 3.37+).
Updating SQLite means a new package version.

## Not in 0.1.0

ORM/schema mapping, virtual tables, custom SQL functions, extension loading, online backup, encryption, replication, async I/O,
connection pooling, cross-thread connection sharing, named-parameter binding by name, incremental blob I/O, Windows.
