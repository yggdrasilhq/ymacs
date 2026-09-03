# vendor/elpa-corpus/ — the step-8 measurement corpus (pinned)

The public corpus that measures ELPA compatibility depth
(`docs/elpa-compat-measurement.md`, instrument `src/elpa/corpus.lisp`).
Deliberately the **blessed modern helper stack itself** plus the
foundation libraries it builds on — the measurement answers the question
"can ymacs load its own blessed stack?", which the "~90%" claim never
did (owner audit 2026-09-02).

Source: **GNU ELPA** (`https://elpa.gnu.org/packages/<name>-<version>.tar`),
fetched 2026-09-03 from the `archive-contents` index of that day.
Each tarball extracts as `<name>-<version>/<name>-<version>/` and is kept
**verbatim** — same doctrine as `docs/emacs-manual/`: never edit a
vendored file in place; each package keeps its own GPL licence header.
GNU ELPA packages are GPL-compatible; this repository is
GPL-3.0-or-later, so the vendoring is licence-clean.

| package | version | sha256 (tar) |
|---|---|---|
| seq | 2.24 | 8693439fd9bc447345aa6e1b5a4121107a474c4e7de5a511bbd2b8586aa0a88f |
| compat | 31.0.0.2 | 47d8693a10087f8b20c72e6a78b628db980cb7547c4f8f517fc5d11acd8b0f38 |
| map | 3.3.1 | 979a32f889a6124816da084c4485a08b130dfe714320457fdd5d77bf9be448fd |
| dash | 2.20.0 | 28f84b0905f84520163f5dd2087e47cac042bd27b7ec34eeb293f1ada7d36cb2 |
| use-package | 2.4.6 | cecba4042a3809b702f6e66eba50f8bc92d1dcc16190e7b09cf1a7772b3abe45 |
| cape | 2.9 | e5a8a474b1de8419cc7b7a88001243f949721fa52aa973aad5cba34e13ac5839 |
| corfu | 2.14 | c6ec346e5666badce80e693ba7fbb9c0e0e02627c200b570f255ba84a4d91aa8 |
| consult | 3.7 | 63f1724728fa7fbcab315e1aef2cf13d647774374b97fb27e8f862d528dbb1a7 |
| marginalia | 2.12 | df85d9e81049cbbbb3f5841fa4f818c5221e51e15149834b1d6da4ee9215423c |
| orderless | 1.7 | 7f65412799662761e6a37d8170ce506ccb7fd236906ed94f7384ec4d65a4333c |
| tempel | 1.14 | c375d362b9d464f4dd4486ead9e091d0fa6c337457a8e32796ece6dc46f15fd4 |
| vertico | 2.13 | 3ac95cd8f9159670b0fbbb7a3f1cfb0c0a9f44c437e44482106837334b422c3a |

Re-pinning: bump the version here with the new sha256, re-run the
instrument, and re-land the numbers — a pin bump that ships without new
numbers violates the honesty law.
