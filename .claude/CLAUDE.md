# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zunpy` is an R package that reads and writes NumPy's array files, `.npy` (one array) and `.npz` (a ZIP of `.npy` members), to and from ordinary R vectors, matrices, arrays and data frames, with no Python installed. It is a *format* package in the `zu*` family, like `zucbor`: one new parser, for the header (a restricted Python literal), over byte-level work that belongs to its providers. `zubin` (`LinkingTo`) owns every typed read and write, half floats and record layouts; `zufast` (`LinkingTo`, header-only) owns UTF-8 validation and the integer parser; `zukomp` (`Imports`) owns raw DEFLATE for compressed `.npz` members. `bit64` is a `Suggests`; NumPy is used only by scripts under `tools/`, never by the R suite. It deliberately has no C API, never evaluates Python, never reads pickles or object arrays, and implements no NumPy semantics.

Two documents outrank this file. [.agents/design.md](../.agents/design.md) is the specification, numbered §1–§21: every statement in it is a decision, and open questions live only in its §18. [.agents/roadmap.md](../.agents/roadmap.md) sequences it into Stages 0–9, each with a **Status:** line under its heading. Both were adopted on 2026-10-08 from [RFC 0003](https://github.com/pedrobtz/packages/blob/main/rfcs/0003-zunpy-numpy-arrays.md) in `pedrobtz/packages`, with the RFC's assumptions about the siblings checked and corrected. `CLAUDE.md` orients, the design decides, the roadmap sequences.

Sibling checkouts are in `../`. `zucbor` is the model for the check-then-build shape, the limits, the conditions, the guards and the mutation check; `zuxml` owns `R/zu_source.R`; `zudedup` is the most recent package to go through the same stages.

## Current state

**2026-10-08: Stages 0–5 done.** `npy_decode()` reads and `npy_encode()` writes every dtype of design §6.1 and §7.1 as raw vectors: numbers, booleans, complex, `S`/`U` strings, `V` bytes (read only), dates and times, and structured dtypes as data frames; `npy_header()` reads a header. The bytes written match `numpy.save()`'s. `.npz` and files are not built yet. Gates: `hardening.yaml` (lint, symbols, mutation check over 19 guards, fuzzing with its canary), `native-checks.yaml` (sanitizers, valgrind, LTO, gctorture, rchk) and `conformance.yaml` (fixtures regenerated with NumPy and checked against `np.load()`, and R-written files read by `np.load()`). zufast, zubin and zukomp are not on CRAN (*verified 2026-10-08*), so the release (Stage 9) waits for all three. Tracking: parent #2, stages #3–#12.

Update this paragraph at the end of every stage.

## Stage tracking

Progress toward the next version is tracked as GitHub sub-issues, so the parent issue shows a progress bar such as "6 of 10".

- **One parent issue per target version**, `v0.1.0`: #2. `.github/scripts/stage-cards.sh` in `pedrobtz/packages` puts it on the board.
- **One sub-issue per roadmap stage**, titled as the roadmap titles it, for example `Stage 1 — The header parser, R-free`, linking to that section's anchor. The roadmap has ten stages, 0 to 9.
- **Every tracking issue carries the `stage` label.**
- **Close a stage by merging its pull request.** Put `Closes #<n>` in the body. Never close a stage whose exit criteria are not met; record a deviation in its **Status:** line first.
- **The roadmap stays authoritative.** Adding, removing or renaming a stage means editing the roadmap and the sub-issues in the same change. Status never goes in a heading.
- Close the parent issue when CRAN accepts the version and it is tagged.

## Versioning

The package develops at `0.0.0.9000` and targets `0.1.0` for its first CRAN release. Set `Version: 0.1.0` and the matching `NEWS.md` heading when the package enters `Pre-flight` (Stage 9). Bump to `0.1.0.9000` only after CRAN accepts it.

Until the first release the R API may change freely. Nothing depends on zunpy. zunpy depends on three siblings before CRAN does: `LinkingTo: zubin, zufast` and `Imports: zukomp`, from `Remotes: pedrobtz/<pkg>@main` during development (zukomp joins at Stage 6). zubin is itself at `0.0.0.9000` and may change its C API before its release; zunpy is its first consumer, so a break is a zubin issue, not a local workaround. **All three must be on CRAN before zunpy is submitted**; `Remotes:` goes at Stage 9 and the release is checked against their CRAN tarballs.

**The bytes zunpy writes are a contract.** Design §8 makes output deterministic and identical to NumPy's; changing the header layout, padding, version choice or `.npz` timestamps is a design change, not a refactor.

## Commands

Run from the package root.

```sh
Rscript -e 'devtools::load_all()'                # compile src/ and load
Rscript -e 'devtools::document()'                # roxygen -> NAMESPACE, man/
Rscript -e 'devtools::test()'                    # full testthat suite
Rscript -e 'devtools::test(filter = "<name>")'   # one test file
Rscript -e 'devtools::test(shuffle = TRUE)'      # order independence
_R_CHECK_SYSTEM_CLOCK_=0 Rscript -e 'devtools::check(cran = TRUE)'
air format .                                     # format R sources
```

The providers are not on CRAN: install them from the sibling checkouts (`R CMD INSTALL ../zufast ../zubin ../zukomp`) or with `pak::pak("pedrobtz/<pkg>")`. roxygen2 must be 8.1.0 or newer.

Gate scripts; those of Stages 0 and 1 exist, the rest arrive at the stage named. The check-phase gates find zufast's headers through `tools/zufast-include` (`$ZUFAST_INC`, else the installed package):

```sh
tools/run-fuzz [secs]          # Stage 1: canary first, then fuzz_header under ASan+UBSan;
                               # macOS: FUZZ_CC=/opt/homebrew/opt/llvm/bin/clang
tools/run-lint                 # Stage 1: -Wall -Wextra -Wpedantic -Wshadow -Werror on project C
tools/check-symbols <so>       # Stage 0: only R_init_zunpy exported; no stdio/abort/exit
tools/run-mutation-check       # Stage 1: every /* GUARD: */ seen to be load-bearing (cases: tools/mutation-cases.R)
Rscript tools/fuzz-seeds.R     # Stage 1: regenerate fuzz/seeds (commit the result)
tools/check-fixtures           # Stage 2: regenerate the NumPy fixtures, diff, check against np.load() (needs uv)
tools/run-benchmarks           # Stage 7: against readBin(), RcppCNPy, reticulate; not a CI gate
```

## Architecture

Planned layout, from design §4, §10 and §13. Today `src/` holds everything below except `znp_zip.c`.

```text
R/            decode.R, header.R, encode.R, read.R, npz.R, structured.R, dtype.R,
              conditions.R, args.R, info.R, zu_source.R (copied verbatim from zuxml),
              zunpy-package.R
src/          init.c          registration only
              znp_r.h         .Call entry points
              znp_info.c      zunpy_info(): provider versions and the LinkingTo self-test
              znp_check.h     the check phase's R-free interface and the plan struct
              znp_header.c    prefix, dict grammar, descr grammar, size check, limits
              znp_r_header.c  .Call glue: the plan as an R list, statuses by name
              znp_build.c     plan -> R value: read_column() reads any dtype at any stride; records as columns
              znp_write.c     header formatted as NumPy does (repr() of field names too); data packed into one raw vector
              znp_perm.c      C order <-> R order, one pass, both directions
              znp_text.c      S, U and V elements, both directions
              znp_time.c      datetime64 / timedelta64 counts <-> doubles, exact or refused
              znp_zip.c       .npz records, CRC-32
              Makevars        hand-listed OBJECTS, $(C_VISIBILITY)
fuzz/         fuzz_header.c (-DZNP_FUZZ_CANARY builds the canary), probe.c, npy.dict, seeds/ (not in the tarball)
tools/        make-fixtures.py, conformance.py, conformance-write.R and the gate scripts above
tests/testthat/fixtures/npy/   NumPy-written files and MANIFEST.tsv
.agents/      design.md, roadmap.md
```

Reading is two phases, as in zucbor. Bytes (from `npy_decode()`, or `npy_read()` after a bounded read) → **check phase** (`znp_header.c`, pure C, no `R.h`): the whole header parsed and validated, the declared size compared with the bytes present → a **plan** (dtype, itemsize, shape, order, data offset) → **build phase** (`znp_build.c`): one allocation from the plan, conversion through zubin's kernels. `.npz` adds a central-directory walk in front and calls the same path once per member. Writing is one pass: the header into a fixed stack buffer, then header and data into a zubin builder held by a finalized external pointer.

## Invariants that are easy to break

- **Nothing is allocated from a header field.** The build phase allocates only from the plan, whose sizes the check phase has compared with the input length. A header claiming `(2**40, 2**40)` must cost nothing (design §12).
- **The header parser is a grammar, never an evaluator.** No identifiers, no arithmetic; recursion capped at depth 8. A valid Python expression outside design §9.2 is a parse error (D12).
- **The check phase never allocates.** It runs in two calls so the caller sizes the scratch from a header length already bounded by `max_header` and the bytes present; anything new the parser stores goes in that scratch, sized in `scratch_layout()`.
- **A guard's `if` is one line.** `tools/run-mutation-check` mutates it with `sed`; a condition split across lines cannot be mutated and fails the check. Each guard needs a case in `tools/mutation-cases.R`.
- **The check phase contains no R.** `znp_header.c` never includes `R.h`; the fuzz build (`-DZNP_STANDALONE`) compiles it standalone.
- **Guards carry `/* GUARD: name */`** on their `if` lines and a `test_that("GUARD name")` each; `tools/run-mutation-check` proves each one is load-bearing. A new guard without its test does not count.
- **Byte order comes from the header, never from the host.** Every read goes through zubin's `le`/`be` kernels; the `memcpy` fast path exists only behind `zb_host_big_endian()` (Stage 7). The `-DZNP_FORCE_BE_HOST` build is how this is tested on a little-endian machine.
- **No byte-level code of zunpy's own** beyond what zubin has no type for: complex as float pairs, UCS-4 strings, `datetime64` classes and ZIP's CRC-32. Byte swapping and narrowing are zubin's.
- **Writing is deterministic and matches NumPy byte for byte** (design §8): key order, quotes, trailing comma, `(n,)`, 64-byte padding, little-endian, fixed `.npz` timestamps. Fixtures prove it; do not "tidy" the header format.
- **Fixture names are lower-case and distinct ignoring case.** macOS file systems are case-insensitive: `M8-M.npy` and `m8-m.npy` were once one file.
- **Strings and lists are moved with `SET_STRING_ELT`/`SET_VECTOR_ELT`**, never `memcpy`: their elements are R pointers under the write barrier (`permute_elements()` in `znp_build.c`).
- **Times: count to double and back is one rule** (`count_to_units()` in `znp_time.c`); the writer accepts a value whose count reads back as the same double. Change both sides together or what is read stops writing back.
- **Exact or refused.** A value that does not fit its target is an error with its index, never rounded or wrapped. `NA` in `logical` or `integer` is refused unless `na = "allow"`.
- **Nothing heap-allocated crosses a longjmp.** Results are R vectors allocated at their final size and `PROTECT`ed; scratch is `R_alloc()`ed. A zubin builder (an external pointer with a finalizer) is for `.npz`, whose size is not known up front.
- **C never calls `Rf_error()`.** Statuses come back by enumerator name and `R/conditions.R` raises; `zubin_error` from `bin_unpack()` and `bin_pack()` is re-raised as the matching `zunpy_` class.
- **Raw DEFLATE is `"deflate-raw"` in zukomp**, not `"deflate"` (which is zlib-wrapped). Always pass `max_output` set to the member's declared size.
- **Portable make only** in `src/Makevars`; hand-listed `OBJECTS`; no `Makevars.win`. `R_init_zunpy` needs `attribute_visible` under `$(C_VISIBILITY)`.

## Naming

| Layer | Prefix | Examples |
|---|---|---|
| R exports | `npy_` plus `zunpy_info()` | `npy_read()`, `npy_encode()`, `npy_dtype()` |
| R condition classes | `zunpy_` | `zunpy_error`, `zunpy_parse_error`, `zunpy_size_limit` |
| R and C internals | `znp_` / `ZNP_` | `znp_header_check()`, `ZNP_STANDALONE` |
| `.Call` entry points | `zunpy_` | `zunpy_header_check` |
| Test-switching variables | `ZUNPY_` | `ZUNPY_SKIP_HEAVY` |

## Testing conventions

- **Self-sufficient.** Every test builds its own inputs inside the `test_that()` block; bytes from hex or from a fixture. No file-scope objects.
- **Self-contained.** Global state through `withr::local_*()`, randomised input through `withr::local_seed()`. Files only under `withr::local_tempdir()`.
- **Assert on condition classes and fields (`offset`, `index`, `dtype`, `member`, `limit`), never message text.** Use `expect_zunpy_error()`.
- **Order independence.** `devtools::test(shuffle = TRUE)` is part of the definition of done; serial, no `Config/testthat/parallel`.
- **The oracle is NumPy, never hand-written expectations.** Fixtures are written by `tools/make-fixtures.py` with NumPy pinned (run it with `uv run --no-project --with numpy==2.3.3 python tools/make-fixtures.py`), recorded in `MANIFEST.tsv` with a SHA-256 and every value (floats as `float.hex()`, which R reads exactly), and never regenerated by a test. `tools/check-fixtures` (the `conformance` job) regenerates them and checks each MANIFEST row against `np.load()`; the R suite checks `npy_decode()` against the same rows. Nothing under `tests/` requires Python. Hostile input is hand-built in `test-hostile.R`.
- **Helpers in `tests/testthat/helper-*.R`**: `helper-bytes.R` (`bytes()`, `npy_header_bytes()`), `helper-fixtures.R` (`fixture_path()`, `fixtures_manifest()`), `helper-expect.R` (`expect_zunpy_error()`, `expect_round_trip()`), `helper-skip.R` (`skip_heavy()` on `ZUNPY_SKIP_HEAVY`, `skip_if_no_numpy()`).
- **Keep the suite inside the CRAN time budget:** under 15 s; the 2 GiB and 10^6-member cases call `skip_heavy()` and run nightly.

## Definition of done

`devtools::document()` and `devtools::check()` clean, meaning 0 errors, 0 warnings and 0 notes. The one allowed note is "New submission" before the first release. `devtools::test(shuffle = TRUE)` green. `gctorture(TRUE)` clean when C changed. CI green on every leg. A user-facing change also needs a test, roxygen documentation and a `NEWS.md` entry. A change to a dtype mapping updates all three copies of the table (design, roxygen, tests) in the same commit. A stage is done when its exit criteria pass in CI on all three platforms; a gate counts once it has been seen to fail.

## Releasing to CRAN

- **CI is the pre-submission check.** The `pedrobtz/r-actions` R CMD check runs `--as-cran` on the CRAN-like runners and containers, and replaces win-builder, the macOS builder and R-hub. `cran-comments.md` lists the CI legs as its test environments.
- **Entering `Pre-flight`.** Stages 0–8 done, `Version: 0.1.0` with the `NEWS.md` heading, `cran-comments.md` written, CI green, zufast, zubin and zukomp on CRAN and `Remotes:` removed.
- **Before submitting,** run the `cran-extrachecks` and `review-cran-submission` skills and resolve every finding.
- **The pretest is automated and does not read `cran-comments.md`.** Fix every NOTE.
- **After acceptance,** tag `v0.1.0`, publish the GitHub release, bump to `0.1.0.9000`, and close the parent issue.

## Editing rules

- roxygen comments are the source. Never edit `man/` or `NAMESPACE` by hand.
- There is no `README.Rmd`; edit `README.md` directly and run its example.
- Prose is simple, short and en-GB (`Language: en-GB`, `inst/WORDLIST`).
- Wrap roxygen at 80 characters; `air format .` on R sources.
- `lower_snake_case`; the naming table above.
- No hard runtime dependency beyond `zukomp` (design D1); add none without a recorded decision. `bit64` stays in `Suggests`.
- Every export has `@return` and runnable `@examples`; no roxygen topics for internals.
- `R/zu_source.R` is copied verbatim from `../zuxml`; fix it there and re-copy.
- `NEWS.md` keeps a versioned heading.

## Continuous integration

Workflows come from `pedrobtz/r-actions`. The scaffold's `R-CMD-check.yaml` (calling `r-cmd-check.yml`), `coverage.yaml` and `pkgdown.yaml` exist at `@v1`; Stage 0 pins `coverage.yaml` by commit, with the tag in a comment, and adds Dependabot. The roadmap's CI table says which stage adds `hardening.yaml` (`fuzz.yml`, lint, symbols, mutation check), `native-checks.yaml` (`sanitizers.yml`, `valgrind.yml`, `lto.yml`, `gctorture.yml`, `rchk.yml`, and the forced-big-endian build) and `conformance.yaml` (NumPy fixtures and `np.load()`). Stage pull requests carry `full-ci`. Nothing is vendored, so there is no `vendor.yaml`.

This file lives in `.claude/`, not the package root, because pkgdown renders every root-level `*.md` as a site page (alignment rule R8 in `pedrobtz/packages`); keep it here.

## Commits and pull requests

Short, imperative, sentence-case commit subjects, optionally scoped. Keep each commit focused and do not sweep in unrelated files. A pull request explains the user-visible outcome and the rationale, links related issues, lists the checks that were run and the tests that were skipped, and flags platform-sensitive changes. Performance claims need evidence from `tools/run-benchmarks`.

Never commit or push to the default branch. Work on a branch (`stage-N-<slug>`), open a pull request, and leave it for review. Do not merge a pull request unless you are told to.

When you find a defect, in this package, in `zubin`, `zufast`, `zukomp` or in an upstream tool, open an issue for it rather than only working around it.
