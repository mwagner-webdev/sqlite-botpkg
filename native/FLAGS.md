# SQLite compile-time options (native/build.sh)

Source: the unmodified upstream amalgamation `sqlite3.c`, SQLite 3.54.1, from
<https://www.sqlite.org/2026/sqlite-amalgamation-3540100.zip> (committed as `native/vendor/`; its SHA3-256,
`92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30`, is the one sqlite.org publishes and `build.sh` refuses any other file).

Compiler: the host `cc` (GCC on Linux, Apple clang on macOS), `-O2 -fPIC`, one object, archived with `ar`.

| option | why |
|---|---|
| `SQLITE_THREADSAFE=1` | serialized mode (sqlite.org default). The package is single-owner per VM regardless; this keeps a connection safe even if an embedder crosses threads. |
| `SQLITE_DQS=0` | double-quoted strings are identifiers only (sqlite.org's recommended setting): no silent string-literal fallback. |
| `SQLITE_OMIT_LOAD_EXTENSION` | no dlopen: extension loading is out of scope and would add a `dl` dependency. |
| `SQLITE_OMIT_SHARED_CACHE` | deprecated feature; not offered. |
| `SQLITE_OMIT_DEPRECATED` | recommended. |
| `SQLITE_DEFAULT_MEMSTATUS=0` | recommended; disables the global memory-statistics mutex. |
| `SQLITE_LIKE_DOESNT_MATCH_BLOBS` | recommended. |
| `SQLITE_USE_URI=0` | file names are paths, never `file:` URIs, so a path with `?` or `#` is a path. |

Not enabled: `SQLITE_ENABLE_MATH_FUNCTIONS` (SQL `sqrt`, `pow`, ...). With it the archive needs `libm` as a *system* library, and the package manager of the pinned compiler cannot install a package declaring one on macOS
(`PM NATIVE: verifying a system library on macos is not implemented`, found by the first macOS CI run). Without it the archive needs only libc and pthread (merged into libc since glibc 2.34; part of libSystem on macOS):
`nm -u` lists no math symbol. The package therefore declares **no system library at all**.

Maintenance policy: bump the pinned amalgamation deliberately (new zip, new SHA3-256 from sqlite.org, new
package version); the CI jobs rebuild it on Linux and macOS and the full acceptance suite runs against it.
