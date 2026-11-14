# SQLITE-BOTPKG-CAPABILITY-CENSUS.md

What Botlish could and could not do for a native, stateful library, established **before** the API was designed.
Labels: **[inspection]** read from the compiler's built-in reference (`botlish -help …`, quoted) or its source;
**[executed]** a command run in the Linux clean-room (probes and logs under `audit/sqlite-botpkg/`);
**[CI]** run by GitHub Actions; **[projected]** proposed, not run. Existing capabilities, proposed abstractions and
observed limitations are kept apart: ✔ exists · ✖ limitation · → what the package did about it.

Compiler under census: `botlish` single-file build, source revision `cdb751b`, SHA-256 `e16550bc…ba86f` — byte-identical to the published
`single-latest` asset (**[executed]** `audit/sqlite-botpkg/logs/environment-linux.log`). The macOS compiler is built from the same commit in CI.

## 1. Package declaration, public surface, dependencies

* ✔ A package is a module tree installed at `.bot_modules/NAME`; it claims its root namespace (`sqlite` → `sqlite.bot`, `sqlite::value` → `sqlite/value.bot`).
  Imports are exact and non-transitive; there are **no re-exports** (`rule.package-modules`) **[inspection]**.
* ✔ `botlish.json` (schema 1–4): `name`, `version`, `dependencies`, per-target `targets` with bundled/system native libraries
  (`cli.packages`) **[inspection]**; `botlish package pack` builds a deterministic `NAME-VERSION.botpkg` **[executed]** (two packs byte-identical, `scripts/pack.sh`).
* ✔ Public surface = every non-`private` declaration of every module. `private fn/struct/type/layout/error` and **`private extern c fn`** exist
  (**[executed]** `private extern` accepted; `nomethod extern` is a syntax error). An `opaque struct` hides a representation from other modules.
* ✖ `error` is a keyword: no module may be called `error` (`sqlite::error` is unusable) **[executed]** F-09.
* → The package is `sqlite` (+ `sqlite::value`, `sqlite::failure`); all C declarations are `private extern`.

## 2. Native libraries: linking and loading; Linux vs macOS

* ✔ `extern c library "NAME" [static [at "PATH"]]` adds a link-plan entry; symbols are resolved by the **system linker at link time**, never at run time
  (`concept.native-link-plan`) **[inspection]**.
* ✔ A package may *bundle* a library per target: `botlish native add FILE -target T -name N` copies it to `targets/T/native/` and records its loader facts;
  the installed view `.bot_modules/.targets/T` carries a `.lib` the compiler links **without `-L`** **[executed]** (`audit/…/logs/` acceptance log shows `native plan`).
* ✔ `native require NAME -target T -origin system` declares a system library **[executed on Linux]**. ✖ On **macOS** `botlish add` refuses any package that declares one: `PM NATIVE: verifying a system library on macos is not implemented` **[CI]** (F-25). → the package declares none: SQLite is built without its optional SQL math functions, so the archive needs only libc/pthread (`nm -u`).
* ✔ The same `extern c library "botsqlite3"` declaration serves Linux and macOS; **no OS conditional in any `.bot` file** **[executed]**.
  Only the per-target archive file differs, and that is package metadata.
* ✔ The compiler accepts **a static archive of one object built by the host `cc`** (`ar rcs`) **[executed]**: SQLite's amalgamation compiled with `-O2 -fPIC`
  links into a PIE executable; `ldd` shows only libm/libgcc/libc (libm is pulled in by Botlish's own runtime, not by the package).
* ✖ `native add -symbol` cannot verify a Mach-O archive built by Apple `ar`: its `__.SYMDEF SORTED` index reads as "0 names" **[CI]** F-16. → The package leaves `-symbol`
  checks to Linux and lets the macOS link be the check.
* ✖ The macOS compiler distribution is not a release asset; it is built from source in CI (`single/macos/build.sh`, ~17 min) **[CI]**. macOS native = **arm64 only, AOT only (no JIT)** **[CI]**
  (`no JIT: ok` in the build log) F-17/F-18.
* ✖ A Linux program that calls C cannot run on `interp`/`compile` (`NATIVE-ONLY`) **[inspection]**; tests are therefore native executables on both OSs.

## 3. How pointers, strings, buffers and nullable values cross the FFI

* ✔ `std::ffi::c::Ptr[T]` is an **affine** C pointer: no arithmetic, no dereference, no integer conversion; `clone`, `erase`, `retype[T]`, `null[T]()`, `null?` (`stdlib.module.std::ffi::c`) **[inspection]**.
* ✔ A pointee may be `Void`, a C integer scalar, `Bool`, `Float/Double`, an `opaque struct` (a C tag identity, declared `opaque struct Db: tag: unit`) or another pointer **[executed]**.
* ✔ C scalars are **integer domains** (`std::ffi::c::Int`, `ULong`, `LongLong`, …): an `int` enters one only where its range is proven (literal, guard, declared parameter type) — a compile-time proof, no wrapping **[executed]**.
* ✔ **Byte borrowing**: `Bytes`/`MutableBytes` reach a *byte-pointee* pointer parameter for one call when the declaration says `read noescape` / `write noescape`; a write returns the updated copy as a
  write-back struct (`filled.dst`) **[executed]** (`memcpy` into a `MutableBytes`). `captures`/unknown escape never admits bytes. No pointer to Botlish storage can be stored.
* ✔ Strings are Bytes: a `const char *` is a `Bytes` the **binding** NUL-terminates (`from_list(encode_utf8(s).append(nul))`) **[executed]**.
* ✔ **Out-parameters** (`sqlite3 **`): allocate a slot natively (`sqlite3_malloc64(16)`), pass `slot.clone().retype[Ptr[Db]]()`, read the pointer back with a
  **native view** of a layout with a pointer field (`std::binary::native::view(PtrSlot, slot).p`) **[executed]**.
* ✔ **Reading C memory of dynamic length** has no primitive (views are fixed-layout, pointers have no arithmetic). → libc `memcpy(dst: write noescape, src: read noescape, n)` into a `MutableBytes`, `strlen` for C strings **[executed]** F-06.
* ✖ **NULL function pointer cannot be made** (`null[T]` accepts data pointees only) **[executed]** F-05. `SQLITE_STATIC` (a NULL destructor) → declare the destructor parameter as `Ptr[Void]`
  (same ABI class) and pass `null[Void]()`. `SQLITE_TRANSIENT` (−1) cannot be expressed at all → bound TEXT/BLOB are copied into `sqlite3_malloc64` buffers the Engine owns and frees (see §8 of the report).
* ✖ **No nullable/Option type** (`capability.null`) and **no payload enum cases** (`enum Value: Integer(int)` is a syntax error) **[executed]** F-03. A C NULL pointer is only `null?`; a SQL NULL needs a library type.
* ✔ `Double` results that are NaN/±Inf become the declared error `NonFiniteFloat` (`concept.c-floats`) **[executed]** (a stored `+Inf` REAL).
* ✔ A foreign call whose pointer parameter *may retain* (`captures`/unknown) is **direct authority**: the calling module must be `direct module` or mediate it through its own context **[executed]** (`-direct`: `module sqlite: contextualized … mediated by sqlite::Engine`).

## 4. Callback-free SQLite

All of the package's operations are callback-free: `sqlite3_exec` with a NULL callback, `prepare/step/column_*`, `bind_*`, `open_v2/close_v2`. No `callback c fn` is needed or used. **[executed]**

## 5. Resource cleanup: declared, triggered, transferred, borrowed

* ✔ `opaque resource struct R:` + `cleanup fn f(r: R, context …)` in the same module: runs **once at the end of the owner's lexical scope** — also on `return`/`fail`/`break` — unless the value moved on first (`concept.resources`) **[executed]** (`Transaction` rolls back when a `fail` leaves its scope).
* ✔ Calling the cleanup (or a function that destructures the resource in its module) is the early release. Moves: binding, argument, result, field, element **[inspection]**.
* ✔ A cleanup has exactly one resource parameter, contexts after it, **no errors clause, unit result**: it cannot fail **[inspection]** → failed cleanup is silent (documented).
* ✖ **Resources cannot be borrowed.** Passing one to a function moves it; reading its affine field is `AFFINE-FIELD-MOVE-REQUIRES-DESTRUCTURE`; a second call is `USE-AFTER-MOVE` **[executed]** F-04 (`repros/f04`).
* ✖ A handler for a call that returns a resource must itself produce a resource; there is none to produce **[executed]** F-13.
* ✔ **Context-owned state** is the sanctioned alternative: an installed context owns affine members (`MutableVector[Slot]`), functions observe them **in place** (`e.conns.element(i).db` as a C-call argument); `pop/take/swap` move one out
  (`concept.context-owned-state`) **[executed]**. Each place use must sit in a function declaring `IndexNotFound`; a handler cannot attach to a field read of an element place.
* ✔ Nothing is released at program end; contexts live for the run; no finalizers (`concept.resources`) **[inspection]** → valgrind: the Engine's 24-byte scratch slot is "definitely lost" **[executed]**.

## 6. Cleanup failures vs. normal errors

Cleanup cannot fail and cannot `fail`; an error in flight when the scope ends is not replaced by cleanup. The package's transaction cleanup swallows rollback errors; `in_transaction?` lets callers check. **[executed]** (`ac_transactions`).

## 7. Errors

* ✔ No exceptions: `error E` (with named payload fields), `fail`, `errors` clauses, one `on E x:` handler per error **by identity only**; no catch-all; unhandled errors are compile errors (`concept.errors`) **[executed]**.
* ✖ An error's payload has **no nameable type** (`Failure` as a parameter type is "unknown type") **[executed]** F-10 → the payload is one named struct, `Failure {info: Info}`.
* ✔ A handler's value must fit the call's type; `return` in a handler leaves the function **[executed]**.
* ✔ Declared errors are proven away where the compiler can (`IndexNotFound` only under specific guard forms, `proof.list-bounds`) **[executed]**.

## 8. Contexts

* ✔ `context struct C` installed with `with context EXPR` — **entry program's top level only, once per type**; callers pass nothing; requirements are derived from the call graph; a function requiring one cannot be a value (`CONTEXT-FUNCTION-VALUE`) **[inspection/executed]**.
* ✔ A module that mediates raw authority through its own context stays "ordinary" (airlock) **[executed]**.
* ✖ An installed context with an unbounded `int` field fails native lowering (`CONTEXT-NATIVE-LOWERING-UNSUPPORTED`); a small-Int domain works **[executed]** F-08 (`repros/f08*`).
* ✔ Functions that *use* the package need not mention its context; the compiler derives it **[executed]** (`-contexts`).
* ✖ `std::test` registers function values, which cannot require a context: tests of context-using code need their own runner **[inspection]** F-19.

## 9. Typed results and nullable values

`List[T]`, `struct`, `enum` (payload-free), integer domains (`type Int64 = Int in …`), `Float64` (finite only), `str`, `Bytes`, no `Option`. A SQL NULL therefore becomes an
**opaque tagged struct** (`Value{kind, integer, real, text, blob}`) with smart constructors, so `==` is value equality and inactive fields are canonical. **[executed]**

## 10. Same package, two operating systems

* ✔ `-target` selects C type sizes and platform namespaces; `std::linux::*` is rejected for macOS targets and vice versa **[executed]** F-01.
* ✖ **No portable way to print.** `std::io` needs `std::linux::io::create()` or `std::darwin::io::create()`; each namespace is rejected on the other OS, and `with context` is only legal in the entry program. A single source file cannot print through `std::io` on both OSs **[executed]** F-01.
  → test/example programs print with libc `write(2)`, remove files with `unlink(2)` and set their exit status with `_exit(2)` (`consumer/posix.bot`) — **F-01/F-02**.
* ✖ A program cannot choose its exit status (`capability.process-exit-status`) **[inspection]**.
* ✔ POSIX libc calls (`write`, `unlink`, `_exit`, `gettimeofday`, `memcpy`, `strlen`) are declared identically on both OSs and ran on Linux **[executed]**; macOS **[CI]**.

## 11. Installing the package for a downstream consumer

`botlish add FILE.botpkg` records `{archive, sha256}` and a lock, installs `.bot_modules/sqlite`, derives the `linux-x86_64` target view (`8 files, 2 native libraries`); `botlish verify` checks installed bytes; `botlish native plan` lists
what links and from where **[executed]**. A consumer needs `cc` for the link; **no download, no hook, no build runs on install**.

## 12. Concurrency boundaries (probed)

Botlish threads (`std::thread`) are native-only VMs sharing no value; each installs its own contexts; start values must be *Sendable*; an opaque struct is not Sendable unless its module declares it.
**[executed]** two threads each ran their own Engine and in-memory database concurrently; sending a `Connection` is a compile-time `THREAD-ENTRY-SIGNATURE` error (`audit/…/logs/threads.log`).

## 13. What the census changed in the design

| census fact | design consequence |
|---|---|
| resources can't be borrowed (F-04) | Engine **context** owns all native handles; user-visible handles are copyable values with generation checks; `Transaction` is a real resource (a guard) |
| no Option / no payload enums (F-03) | `Value` = opaque tagged struct; typed accessors fail with `ColumnError`; `*_or(default)` for explicit defaults |
| no NULL fn pointer, no `SQLITE_TRANSIENT` (F-05) | bound TEXT/BLOB are copied into Engine-owned buffers passed as `SQLITE_STATIC` and freed on reset/finalize |
| no dynamic-length reads (F-06) | libc `memcpy`/`strlen` with byte borrowing |
| cleanup can't fail; context state never released | rollback errors swallowed (documented); `open_connections()`/`open_statements()` counters; `close` is explicit |
| errors selected by identity only | one `Failure` error + stable `ErrorKind`; separate errors only for non-SQLite conditions (`NoRows`, `ColumnError`) |
| no portable stdout/exit (F-01/F-02) | tests use libc `write`/`_exit`; a runner script also checks the `RESULT` line |
| `std::test` can't carry contexts (F-19) | a 60-line harness context |
