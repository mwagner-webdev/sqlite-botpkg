# sqlite-botpkg — SQLite 3 as a portable Botlish package (clean-room milestone 1)

An independently maintained Botlish package over the **original upstream SQLite 3.54.1 amalgamation**, with an Engine context,
generation-checked handles, resource-safe transactions, and an acceptance suite that runs on **Linux x86-64** and **macOS arm64**.

* Start with `SQLITE-BOTPKG-CLEANROOM-MILESTONE-1.md` (result, evidence, acceptance matrix).
* `SQLITE-BOTPKG-CAPABILITY-CENSUS.md` — what Botlish could do for a native stateful library, before the design.
* `SQLITE-BOTPKG-LANGUAGE-FINDINGS.md` — the defect/awkwardness ledger, with SQLite-free reproducers.
* `sqlite/README.md` — the package's own documentation (API, ownership, errors, transactions, setup).

## Layout

| path | what |
|---|---|
| `sqlite/` | the package source: `botlish.json`, `sqlite.bot`, `sqlite/value.bot`, `sqlite/failure.bot`, `README.md`, `NOTICE-SQLITE.txt` |
| `native/` | `build.sh` (pinned amalgamation → `libbotsqlite3.a`), `vendor/` (the verified upstream zip), `FLAGS.md` (compile options and maintenance policy) |
| `consumer/` | the **independent consumer project**: acceptance programs `ac_*.bot`, interop, two applications (`tasklist`, `kv`), `bench.bot` — imports only the installed package |
| `scripts/` | `pack.sh`, `run_acceptance.sh`, `oracle.sh`, `fetch_oracle.sh`, `valgrind.sh` |
| `bench/` | `bench.c`: the same workload through SQLite's C API |
| `audit/sqlite-botpkg/` | probes, minimal reproducers (`repros/`, `run_repros.sh`), logs of every executed command |
| `.github/workflows/ci.yml` | builds the macOS compiler, both native archives, the package; runs the suite on Linux and on macOS arm64 |

## Reproduce

```sh
# Linux x86-64: compiler = the single-file binary pinned in .github/workflows/ci.yml (SHA-256 e16550bc…)
curl -fsSL https://github.com/mwagner-webdev/botlish/releases/download/single-latest/botlish-linux-x86_64 -o botlish && chmod +x botlish
BOT=$PWD/botlish scripts/pack.sh                    # builds the archive from the pinned amalgamation, packs dist/sqlite-0.1.0.botpkg (twice, byte-compared)
scripts/fetch_oracle.sh build/oracle                # sqlite.org's own sqlite3 shell, SHA3-256 verified
BOT=$PWD/botlish scripts/run_acceptance.sh dist/sqlite-0.1.0.botpkg      # fresh project, install, build natively, run everything (~6 min)
scripts/valgrind.sh build/consumer-run              # memory check of the C boundary
audit/sqlite-botpkg/run_repros.sh                   # the language findings' reproducers
```

On macOS the same `scripts/*.sh` run unchanged against the compiler CI builds (`compiler-macos` job); CI is the only macOS evidence this repository claims.
