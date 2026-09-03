# Vendored Common Lisp dependencies

Imported ecosystems (the same doctrine as Rust's vendored crates):
import, never hand-roll. Debian source packages, unmodified except for
file-set trimming noted per package. Runtime system library required:
`libsqlite3` (Debian/Ubuntu package `libsqlite3-0`; installed by
default on desktop hosts).

| package | version source | license | notes |
|---|---|---|---|
| cffi 0.24.1 | Debian cl-cffi | MIT | trimmed to cffi.asd + src/ grovel/ toolchain/ (tests, examples, uffi-compat, libffi dropped) |
| sqlite 20130615 | Debian cl-sqlite | MIT | sqlite-tests.lisp dropped |
| alexandria | Debian cl-alexandria | BSD-2-clause | unmodified |
| babel | Debian cl-babel | MIT | unmodified |
| iterate | Debian cl-iterate | MIT | unmodified |
| trivial-features | Debian cl-trivial-features | MIT | unmodified |
| trivial-gray-streams | Debian cl-trivial-gray-streams | MIT | unmodified |

Upstream licensing headers are kept inside each package directory.
