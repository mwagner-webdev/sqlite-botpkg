# SQLITE-BOTPKG-LANGUAGE-FINDINGS.md

The defect-and-awkwardness ledger of the clean-room sqlite package. Compiler: `botlish` source revision `cdb751b` (Linux binary SHA-256 `e16550bc…`; macOS built from the same commit in CI).
Every reproducer is under `audit/sqlite-botpkg/repros/`; `audit/sqlite-botpkg/run_repros.sh` re-runs them and the output is in `audit/sqlite-botpkg/logs/repros.log`.
Labels: **[executed]** run on Linux; **[CI]** run by GitHub Actions; **[inspection]** read from the compiler's reference.
Class: **semantic** (changes what a program can express), **ergonomic**, **library primitive** (a missing std/ecosystem piece), **tooling**, **performance**.
Severity: **blocker** (no natural implementation), **major** (forces a design the language owners should know about), **minor**.
"Genuine language issue?" separates a real limitation from a package-design mistake.

None of these needed a change to the compiler or runtime; every workaround is a library-level, documented one.

## Summary

| id | finding | subsystem | class | severity | reproducible without SQLite |
|---|---|---|---|---|---|
| F-04 | resources cannot be borrowed → no resource-typed connection | affine values / resources | semantic | **major** | yes (`f04/`) |
| F-01 | no portable way to print; platform I/O namespaces rejected cross-target | stdlib / platform | semantic + ergonomic | **major** | yes (`f01_*`) |
| F-03 | no Option, no payload enum cases → SQL NULL / sum types need a tagged struct | types | semantic | **major** | yes (`f03_*`) |
| F-05 | NULL function pointer cannot be created; `SQLITE_STATIC/TRANSIENT` unrepresentable | FFI | library primitive | **major** | yes (`f05_*`) |
| F-06 | no primitive to copy dynamic-length native memory into Bytes | FFI / binary | library primitive | minor (libc `memcpy` works) | — |
| F-08 | context with an unbounded `int` field fails native lowering | contexts / native backend | semantic (backend gap) | minor | yes (`f08_*`) |
| F-02 | no exit status for programs | runtime | library primitive | minor (libc `_exit` works) | — |
| F-16 | package manager cannot read Mach-O archive symbol index | package manager | tooling | minor | needs a macOS archive |
| F-17 | no macOS compiler release asset; build from source ≈ 17 min | distribution | tooling | minor | — |
| F-10 | error payload has no nameable type | errors | ergonomic | minor | yes (`f10_*`) |
| F-13 | a handler cannot "just record" a failed resource-returning call | affine values | ergonomic | minor | yes (`f13_*`) |
| F-09 | `error` is a keyword, so `sqlite::error` cannot be a module | syntax | ergonomic | minor | yes (`f09_*`) |
| F-12 | every use of a context-owned element place needs its own `IndexNotFound`-declaring function | contexts / collections | ergonomic | minor | — |
| F-19 | `std::test` cannot hold tests of context-using code | stdlib | ergonomic | minor | — |
| F-14, F-15, F-20, F-21, F-23 | lint / syntax awkwardness (below) | lints, syntax | ergonomic | minor | partly |
| F-24 | `Float64` has no ±Infinity: a stored `REAL` ±Inf is unreadable as a number | numbers | semantic | minor | — |
| F-18 | macOS native backend: arm64 only, AOT only | backend | tooling | minor | — |
| F-25 | `botlish add` refuses any package declaring a *system* native library on macOS | package manager | tooling | **major for portability** (found by the first macOS run) | needs a package + macOS |
| F-22 | context-owned native state is never released at exit | resources | semantic | minor | — |

Nothing here is a hard blocker: every item had a legitimate library-level answer. F-04 is the one that most changed the library's shape.

---

## F-04 — resources cannot be borrowed  *(major, semantic; genuine language limitation)*

* **Intended operation.** `db = sqlite::open(path)` returns a connection that is a *resource* (closed at scope end, impossible to double-close), then `db.execute(a)`, `db.execute(b)`, `db.close()`.
* **Reproducer.** `audit/sqlite-botpkg/repros/f04/{handle,main}.bot` — `h = handle::open(1); a = handle::id_of(h); b = handle::id_of(h)`.
* **Observed** **[executed]**: `USE-AFTER-MOVE: h was used after its affine value was moved — h passed to handle::id_of`. Passing a resource moves it; reading its affine field is `AFFINE-FIELD-MOVE-REQUIRES-DESTRUCTURE`; a destructure in the declaring module *discharges* it (no cleanup). There is no `&`, no borrow parameter, no "observe" mode for user functions (only C calls observe).
* **Subsystem.** affine values / resources (`concept.resources`, `concept.affine`).
* **Class.** semantic. **Genuine language issue?** Yes — it is a documented design point ("no reference counts, no borrow"), and a library built on it cannot offer a resource-typed handle that serves more than one call. Not a package-design mistake.
* **Workaround.** The `Engine` *context* owns the native handles in `MutableVector`s and functions observe them in place (`concept.context-owned-state`); the user-visible `Connection`/`Statement` are **unrestricted generation-checked handle values**. This keeps memory safety (a stale handle is *detected*, never dereferenced; a reused slot gets a new generation; closing twice is a `misuse` Failure) but loses static "use after close is impossible". `Transaction` *is* a real resource, used only as a guard that is not threaded through calls.
* **Suggested follow-up.** A **borrow/observe parameter mode** for resources (a parameter that observes an affine value for the call without taking ownership; the caller keeps the obligation) — or lifting "observation" (already granted to C calls and element places) to functions that only pass the value on to observation positions. *Why a language change is justified:* the same wall hits every handle-style library (files, sockets, DB handles, GPU resources): today each must reinvent a generation-checked handle table, which is exactly the class of runtime check the resource system exists to remove. A sound observation mode needs no new run-time state (the compiler already tracks a single owner).

## F-01 — no portable stdout; platform I/O namespaces are rejected cross-target  *(major, semantic + ergonomic)*

* **Intended operation.** One test/example `.bot` that prints, identical on Linux and macOS.
* **Reproducer.** `f01_portable_stdout.bot`.
* **Observed** **[executed]**: `-check` on Linux → `UNSUPPORTED-PLATFORM: namespace "std::darwin::io" belongs to the macOS platform … unavailable for target linux-x86_64`; `-target macos-aarch64` → `ok`. `std::io::print_line` needs a context installed with `with context std::linux::io::create()` **or** `std::darwin::io::create()`, and `with context` is legal only in the entry program, so the choice cannot live in a library module or behind a conditional.
* **Class.** semantic (a documented rule) with an ergonomic cost. **Genuine language issue?** Yes for the "same consumer source on both OSs" requirement: there is no portable `std::io` installer.
* **Workaround.** `consumer/posix.bot` binds POSIX `write(2)` (and `unlink(2)`, `_exit(2)`) through `extern c fn`: portable over libc, but it bypasses `std::io` and duplicates it. It lives in the *test/example* code, not the package.
* **Suggested follow-up.** A portable `std::io::create()` (resolved per target at link time, like `extern c library`), or allowing a context *constructor* to be selected by target. Justified because it is the first thing every cross-platform CLI needs and today forces per-OS entry files — against the stated goal "no operating-system conditionals".

## F-03 — no Option, no payload enum cases  *(major, semantic)*

* **Intended operation.** `enum Value: Null, Integer(Int64), Real(Float64), Text(str), Blob(Bytes)`; "explicit nullable/optional value".
* **Reproducer.** `f03_payload_enum.bot`. **Observed** **[executed]**: `SURFACE SYNTAX: enum case "Integer" cannot take a parameter list … (payload-bearing cases are not supported)`; `capability.null`: no null/nil/optional.
* **Class.** semantic. **Genuine?** Yes (documented "no payloads (yet)"; a later upstream commit mentions payload enums).
* **Workaround.** `sqlite::value::Value` is an *opaque struct* `{kind, integer, real, text, blob}`; only the module's smart constructors build one, so inactive fields are canonical and `==` is SQLite value equality; NULL has its own `Kind::Null`. Accessors fail with one `ColumnError`; `*_or(default)` take an explicit default.
* **Follow-up.** Payload enums (already planned upstream). Not proposed here beyond that.

## F-05 — a NULL function pointer cannot be created  *(major for FFI, library primitive)*

* **Intended operation.** `sqlite3_bind_text64(stmt, i, ptr, n, SQLITE_STATIC /* NULL */, enc)`; or `SQLITE_TRANSIENT /* (void(*)(void*))-1 */`; or a NULL callback to `sqlite3_exec`.
* **Reproducer.** `f05_null_fnptr.bot`. **Observed** **[executed]**: `IMPRINT: std::ffi::c::null: T … Fn{…} has no C representation: a pointee is Void, a C integer scalar, Bool, Float, Double, an opaque struct or another pointer`. `null?` accepts function pointers; nothing creates one. `FnPtr` is also not creatable from a C symbol, and a `callback c fn` is refused when invoked outside the one call that received it.
* **Class.** library primitive (missing FFI capability). **Genuine?** Yes.
* **Workaround (library-level, documented, not a patch).** Declare the destructor/callback parameter as `Ptr[Void]` — same ABI class, **only** ever passed `null[Void]()` — so `SQLITE_STATIC` works. `SQLITE_TRANSIENT` (−1) has no spelling, so the package **copies every bound TEXT/BLOB into a `sqlite3_malloc64` buffer owned by the Engine** (`Buffer` arena), binds it static, and frees it at `reset`/`finalize`/`close`. That is ~40 lines the C idiom does not need, and the risk is the package's (hence valgrind runs, below). No C shim, no generated source.
* **Follow-up.** `std::ffi::c::null_fn[Fn{…}]()` (a NULL function pointer) and, for sentinel destructors, an `unsafe`-free way to name a C library symbol's address as an `FnPtr` (`std::ffi::c::symbol(NAME)`). Justified: both are common in C APIs (`SQLITE_STATIC`, `SIG_IGN`, NULL callbacks) and cannot be worked around without lying about a parameter's type.

## F-06 — copying dynamic-length native memory  *(minor, library primitive)*

* **Intended.** `bytes = std::abi::bytes::copy_from(ptr, n)` for a pointer SQLite returned (`sqlite3_column_text`/`_blob`, error messages).
* **Observed** **[inspection + executed]**: pointers have no arithmetic; `std::binary::native::view` needs a fixed-size layout; no `Bytes`-from-pointer exists.
* **Workaround.** libc `memcpy(dst: write noescape, src: read noescape, n)` into a `MutableBytes` (write-back) and `strlen` for C strings: portable on Linux and macOS, both `noescape` so they are not direct authority. ~10 lines.
* **Follow-up.** `std::abi::bytes::copy_from(Ptr[Void], n)` (a copy-in primitive) — small, general, removes a libc dependency from every binding.

## F-08 — context with an unbounded `int` field fails native lowering  *(minor, backend gap)*

* **Reproducers.** `f08_context_int.bot` (fails), `f08b_context_int_domain.bot` (works). **Observed** **[executed]**: `CONTEXT-NATIVE-LOWERING-UNSUPPORTED: context Ident cannot currently be stored in a fixed native context slot because field "id" is an Int whose declared domain does not fit the small-Int representation`.
* **Class.** semantic gap in the native backend (the Tcl backends accept it). **Genuine?** Yes — a documented limitation with a precise message.
* **Workaround.** `type EngineIdent = Int in 0..4503599627370495` (52 bits).
* **Follow-up.** Register such fields as GC roots in the context slot (the message itself names the cause).

## F-02 — a program cannot choose its exit status  *(minor, library primitive)*

* `capability.process-exit-status` **[inspection]**. A failing test must exit non-zero: the harness calls libc `_exit(1)` (`consumer/posix.bot`), and the runner also requires the `RESULT passed=N failed=0` line (a crash or a missing line fails too). **Follow-up:** `std::process::exit(status)`; not argued further — libc works.

## F-16 — the package manager cannot read a Mach-O archive's symbol index  *(minor, tooling)*

* **Observed** **[CI]** (artifact of run 43470724971, inspected on Linux): `botlish native inspect libbotsqlite3.a -target macos-aarch64` → `index: 0 names` for an archive whose first member is Apple `ar`'s `#1/20 __.SYMDEF SORTED`; `native add … -symbol sqlite3_bind_blob64` → `does not define the declared symbol`. The audit then marks macOS "partially verified". **Workaround:** `-symbol` checks are Linux-only (`scripts/pack.sh`); the macOS link in CI is the check. **Follow-up:** parse BSD `__.SYMDEF[ SORTED]` (and note Mach-O symbols carry a leading `_`).

## F-17 / F-18 — macOS compiler distribution  *(minor, tooling)*

* No macOS asset exists on the Botlish releases (`gh release list`); the CI builds `Botlish.app` from the pinned commit (`single/macos/build.sh`, Tcl 9.0.1 + Rust, ~17 min on `macos-15`). The macOS distribution has **no JIT** and macOS native is **arm64 only**, so macOS tests are native executables only — which the milestone requires anyway.

## F-25 — a package that declares a system library cannot be installed on macOS  *(tooling; found by the first macOS CI run)*

* **Intended operation.** declare `libm` as a system library for both targets (`native require m -target T -origin system`) because SQLite's math functions need it, and install the package on macOS.
* **Observed** **[CI]** (run 43497669917, `macos-15` arm64, `logs/ci-run-43497669917-macos-FAILED-install-system-libm.raw.log`): `botlish add sqlite-0.1.0.botpkg` →
  `error: the native dependencies of the packages for macos-aarch64: system library m: verifying a system library on macos is not implemented (the plan reports it unverified) (declared by instance sqlite) (PM NATIVE)`. The same package packs and installs on Linux, and `package pack` on Linux accepts the macOS entry as "partially verified" — so the problem only appears at *install* time on the consumer's Mac.
* **Class.** tooling. **Genuine?** Yes (a documented-by-message gap; "reports it unverified" is how `native plan` is meant to treat it, but `add` treats it as fatal).
* **Workaround (design change).** Build SQLite without `SQLITE_ENABLE_MATH_FUNCTIONS`; `nm -u` then shows no libm symbol, so no system library is declared at all. The SQL math functions are a documented non-feature (`native/FLAGS.md`).
* **Follow-up.** Make an *unverifiable* system library a warning at install time (the plan already "reports it unverified"), or implement the macOS check (libSystem's `.tbd`). Justified: every macOS package with a system library (`libz`, `libm`, `libsqlite3`) is uninstallable until then, and the failure shows up only on the consumer's machine.

## F-10 — error payloads have no nameable type  *(minor)*

* `f10_error_payload_type.bot` → `unknown type "Failure"` **[executed]**. A helper `describe(f: Failure)` cannot be written; an untyped parameter loses the field types (`any`). **Workaround:** the error carries one nameable struct, `Failure {info: Info}`, and helpers take `Info`. **Follow-up:** make `E` a type name for its payload (`fn f(p: E)`), tiny and local.

## F-13 — a handler cannot merely record a failed resource-returning call  *(minor)*

* `f13_affine_handler.bot` → `AFFINE-NOT-DEFINITELY-LIVE`: the handler of `g = acquire(1)` must yield a `Guard`; the only one in reach is moved. **Workaround:** test "this begin must fail" as a predicate function that `return`s from the handler (`ac_contention.bot: begin_is_busy?`). Pure language ergonomics; no change proposed.

## F-09, F-12, F-14, F-15, F-19, F-20, F-21, F-23 — small awkwardnesses  *(minor; no change proposed)*

* **F-09** `error` is a keyword: no module path segment `error` (`f09_error_keyword_module.bot`). Renamed `sqlite::failure`.
* **F-12** An element place of a context-owned `MutableVector` is usable only as an argument inside a function that declares `IndexNotFound`; a handler on the *use* does not cover it (`std::mutable_vector::element`). The package has ~25 two-line wrappers (`c_step`, `c_reset`, …) — mechanical, not hard.
* **F-14** `METHOD-ELIGIBLE` fires on every `extern c fn` call with ≥ 2 parameters and `nomethod extern` is a syntax error, so externs are called receiver-first (`db.sqlite3_busy_timeout(ms)`), which reads oddly. A warning-free package was a goal, so the package does that.
* **F-15** `ONE-CHAR-STRING-LITERAL` also fires on *data* strings (`value::text("a")`); tests use longer strings.
* **F-19** `std::test` cases are function values, and a function requiring a context cannot be a value → a context-using library needs its own runner (`consumer/harness.bot`).
* **F-20** No numeric string escapes (`\0`, `\u{…}`): strings with NUL bytes are built by `decode_utf8` of a byte list (NUL in `str` itself works, **[executed]**).
* **F-21** Two modules defining `init(db)` make `db.init()` ambiguous; the qualified call `apps::taskdb::init(db)` is fine and warning-free. (Same as the earlier tui milestone's `repros/method-ambiguity`.)
* **F-23** `xs.at(i)` is proven only for a few guard shapes (`if i < 0 or i >= xs.length(): return`); others need a handler.

## F-24 — Float64 has no ±Infinity  *(minor, semantic)*

* SQLite can store `Inf` (`select 9e999` is a REAL +Inf). `sqlite3_column_double` yields `NonFiniteFloat` at the C boundary (`concept.c-floats`), so the package reports a `Failure` of kind `encoding` for that read **[executed]** (`ac_values: infinity`). Reading it as TEXT (`cast(x as text)` = `"Inf"`) always works. `-0.0` reads as `0.0` (no negative zero). This is the language's documented numeric model; the package makes the consequence explicit instead of clamping.

## F-22 — context-owned native state is never released at exit  *(minor)*

* `concept.resources`: "nothing is released at the program's end". valgrind reports the Engine's 24-byte scratch slot as definitely lost in every acceptance program **[executed]** (`logs/valgrind-summary.log`). Open connections/statements are the application's to `close`; `open_connections()`/`open_statements()` expose what is left. A direct context member cannot be moved out and freed; a collection member could, at the cost of one more IndexNotFound wrapper — not worth it for 24 bytes.

---

## Bugs found *in the package* by the independent checks (not language findings)

* **valgrind** found that `sqlite3_prepare_v2` read one byte past its SQL buffer (`nByte` = length of the NUL-terminated bytes **+ 1**). Fixed (`c_prepare(ci, text, n)`); after the fix 9 acceptance programs run with **0** memory errors **[executed]** (`audit/sqlite-botpkg/logs/valgrind-summary.log`; the pre-fix log is the reason the section exists). No functional test could see it: the byte after the buffer happened to be addressable.
* The sqlite3 CLI oracle disagreed with a hand-counted byte length in the test script (25, not 24); the test, not the package, was wrong.
