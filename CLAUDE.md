# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Shared conventions

The portfolio's shared rules are synced into `.claude/shared/` from
`pedrobtz/packages:claude/shared/`. Never edit them here. Where this file and
a shared file disagree, this file wins for this package.

@.claude/shared/workflow.md
@.claude/shared/r-package.md
@.claude/shared/ci.md
@.claude/shared/correctness.md
@.claude/shared/assurance.md

## What this is

`zunpy` is an R package that reads and writes NumPy's array files, `.npy` (one
array) and `.npz` (a ZIP of `.npy` members), to and from ordinary R vectors,
matrices, arrays and data frames, with no Python installed. It is a *format*
package in the `zu*` family, like `zucbor`: one new parser, for the header (a
restricted Python literal), over byte-level work that belongs to its providers.
`zubin` (`LinkingTo`) owns every typed read and write, half floats and record
layouts; `zufast` (`LinkingTo`, header-only) owns UTF-8 validation and the
integer parser; `zukomp` (`Imports`) owns raw DEFLATE for compressed `.npz`
members. `bit64` is a `Suggests`; NumPy is used only by scripts under `tools/`,
never by the R suite. It deliberately has no C API, never evaluates Python,
never reads pickles or object arrays, and implements no NumPy semantics.

Two documents outrank this file. [.agents/design.md](.agents/design.md) is the
specification, numbered §1–§21: every statement in it is a decision, and open
questions live only in its §18. [.agents/roadmap.md](.agents/roadmap.md)
sequences it into Stages 0–9, each with a **Status:** line under its heading.
Both were adopted on 2026-10-08 from [RFC
0003](https://github.com/pedrobtz/packages/blob/main/rfcs/0003-zunpy-numpy-arrays.md)
in `pedrobtz/packages`, with the RFC's assumptions about the siblings checked
and corrected. `CLAUDE.md` orients, the design decides, the roadmap sequences.

Sibling checkouts are in `../`. `zucbor` is the model for the check-then-build
shape, the limits, the conditions, the guards and the mutation check; `zuxml`
owns `R/zu_source.R`; `zudedup` is the most recent package to go through the
same stages.

## Current state

**2026-11-14: Stages 0–8 done; Version 0.1.0 ready to submit.** The
whole API of design §5 exists and is documented, with a vignette
(`vignette("zunpy")`) and a real README: `npy_read()`/`npy_write()` over paths,
URLs and connections, `npy_decode()`/`npy_encode()` over raw vectors,
`npy_header()`, `npy_names()`, `npy_dtype()`, `zunpy_info()`. Every dtype of
§6.1 and §7.1 both ways (structured as data frames, `.npz` as named lists);
bytes written match `numpy.save()`'s and, stored, `numpy.savez()`'s. Benchmarks
are in design §16. The release review #25 is fixed, `Remotes:` is gone and
`LinkingTo: zubin (>= 0.1.0)`: zufast, zukomp and zubin 0.1.0 are all on CRAN
(*verified 2026-11-14 against crandb*), and the nightly fuzz week is met.
Stage 9 (#12) stays open until CRAN accepts; what is left is the submission.

After 0.1.0, #30 (safetensors read and write) is planned for v0.2.0.

Update this paragraph at the end of every stage, and the stage's **Status:**
line in the roadmap with it.

## Versions and dependents

The current version's parent issue is
[#2](https://github.com/pedrobtz/zunpy/issues/2) for `v0.1.0`, with
stages #3–#12 (ten stages, 0 to 9). `.github/scripts/stage-cards.sh` in
`pedrobtz/packages` puts it on the board. In the roadmap each stage has a
**Status:** line under its heading; status never goes in a heading, and a
deviation is recorded in that line before its stage closes.

Sibling packages that depend on this one: none. zunpy depends on three
siblings, `LinkingTo: zubin, zufast` and `Imports: zukomp`, through their CRAN
releases (`Remotes:` was removed at Stage 9, 2026-11-14, once all
three were accepted). zunpy is zubin's first consumer, so a break in zubin's C
API is a zubin issue, not a local workaround. A release of zunpy is checked
against its providers' CRAN tarballs.

**The bytes zunpy writes are a contract.** Design §8 makes output deterministic
and identical to NumPy's; changing the header layout, padding, version choice or
`.npz` timestamps is a design change, not a refactor.

## Commands

The everyday commands are in `.claude/shared/r-package.md`. Run R CMD check as
CRAN does, with the system-clock check off:

```sh
_R_CHECK_SYSTEM_CLOCK_=0 Rscript -e 'devtools::check(cran = TRUE)'
Rscript -e 'spelling::spell_check_package(".")'
```

The providers are on CRAN: `install.packages(c("zubin", "zufast", "zukomp"))`.
To try a provider's unreleased change, install it from its sibling checkout
(`R CMD INSTALL ../zubin`).
roxygen2 must be 8.1.0 or newer.

Gate scripts. The check-phase gates find zufast's headers through
`tools/zufast-include` (`$ZUFAST_INC`, else the installed package):

<!-- markdownlint-disable MD013 -->
```sh
tools/run-fuzz [secs]          # Stages 1, 6: each canary first, then fuzz_header and fuzz_zip under ASan+UBSan;
                               # macOS: FUZZ_CC=/opt/homebrew/opt/llvm/bin/clang
tools/run-lint                 # Stage 1: -Wall -Wextra -Wpedantic -Wshadow -Werror on project C
tools/check-symbols <so>       # Stage 0: only R_init_zunpy exported; no stdio/abort/exit
tools/run-mutation-check       # Stage 1: every /* GUARD: */ seen to be load-bearing (cases: tools/mutation-cases.R)
Rscript tools/fuzz-seeds.R     # Stage 1: regenerate fuzz/seeds (commit the result)
tools/check-fixtures           # Stage 2: regenerate the NumPy fixtures, diff, check against np.load() (needs uv)
tools/run-benchmarks [n]       # Stage 7: against readBin()/writeBin() (and RcppCNPy if installed); not a CI gate
```
<!-- markdownlint-enable MD013 -->

`tools/npy-bytes.R` builds a `.npy` laid out as NumPy lays it out, for
`tools/fuzz-seeds.R` and `tools/mutation-cases.R`;
`tests/testthat/helper-bytes.R` has the same builder for the suite.
`tools/conformance-write.R DIR` is the R side of the writing conformance check,
read by `tools/conformance.py`. `tools/run-benchmarks` runs
`tools/benchmarks.R`; its results are recorded in design §16.

## Architecture

The layout, from design §4, §10 and §13:

<!-- markdownlint-disable MD013 -->
```text
R/            decode.R, header.R, encode.R, read.R, npz.R,
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
              znp_zip.h       the .npz directory check's R-free interface
              znp_zip.c       .npz directory check (guards), CRC-32, the archive writer
              znp_r_zip.c     .Call glue: the member table, CRC-32, building an archive
              Makevars        hand-listed OBJECTS, $(C_VISIBILITY)
fuzz/         fuzz_header.c, fuzz_zip.c (-DZNP_FUZZ_CANARY builds each canary), probe.c, npy.dict,
              seeds/, seeds-zip/ (not in the tarball)
tools/        make-fixtures.py, conformance.py, conformance-write.R and the gate scripts above
tests/testthat/fixtures/npy/   NumPy-written files and MANIFEST.tsv
.agents/      design.md, roadmap.md
```
<!-- markdownlint-enable MD013 -->

Reading is two phases, as in zucbor. Bytes (from `npy_decode()`, or `npy_read()`
after a bounded read) → **check phase** (`znp_header.c`, pure C, no `R.h`): the
whole header parsed and validated, the declared size compared with the bytes
present → a **plan** (dtype, itemsize, shape, order, data offset) → **build
phase** (`znp_build.c`): one allocation from the plan, conversion through
zubin's kernels. `.npz` adds a central-directory walk in front and calls the
same path once per member. Writing is one pass: the header into a fixed stack
buffer, then header and data into a zubin builder held by a finalized external
pointer.

## Invariants that are easy to break

- **Nothing is allocated from a header field.** The build phase allocates only
  from the plan, whose sizes the check phase has compared with the input length.
  A header claiming `(2**40, 2**40)` must cost nothing (design §12).
- **The header parser is a grammar, never an evaluator.** No identifiers, no
  arithmetic; recursion capped at depth 8. A valid Python expression outside
  design §9.2 is a parse error (D12).
- **The check phase never allocates.** It runs in two calls so the caller sizes
  the scratch from a header length already bounded by `max_header` and the bytes
  present; anything new the parser stores goes in that scratch, sized in
  `scratch_layout()`.
- **`do.call()` with a `call` argument needs `quote = TRUE`**, or the stored
  call is evaluated and the caller's expression runs again.
- **zukomp's `max_output = 0` means no cap.** Inflate a member with `max(usize,
  1)` and then check the length.
- **A guard's `if` is one line.** `tools/run-mutation-check` mutates it with
  `sed`; a condition split across lines cannot be mutated and fails the check.
  Each guard needs a case in `tools/mutation-cases.R`.
- **The check phase contains no R.** `znp_header.c` never includes `R.h`; the
  fuzz build (`-DZNP_STANDALONE`) compiles it standalone.
- **Guards carry `/* GUARD: name */`** on their `if` lines and a
  `test_that("GUARD name")` each; `tools/run-mutation-check` proves each one is
  load-bearing. A new guard without its test does not count.
- **Byte order comes from the header, never from the host.** Every read goes
  through zubin's `le`/`be` kernels; the `memcpy` fast path (`znp_fast_path()`
  in `znp_r.h`, and `znp_read_direct()` in `R/read.R`) exists only for
  little-endian data on a little-endian host. The `-DZNP_FORCE_BE_HOST` build
  (`native-checks.yaml`) runs the suite without it; set `ZUNPY_FORCED_BE` when
  running such a build locally, as `test-info.R` checks the flag took.
- **An argument before `...` partially matches.** `npy_read(f, na = ...)` once
  set `names`; arguments of `npy_read()` and `npy_write()` other than the first
  ones go after `...`.
- **No byte-level code of zunpy's own** beyond what zubin has no type for:
  complex as float pairs, UCS-4 strings, `datetime64` classes and ZIP's CRC-32.
  Byte swapping and narrowing are zubin's.
- **Writing is deterministic and matches NumPy byte for byte** (design §8): key
  order, quotes, trailing comma, `(n,)`, 64-byte padding, little-endian, fixed
  `.npz` timestamps. Fixtures prove it; do not "tidy" the header format.
- **Fixture names are lower-case and distinct ignoring case.** macOS file
  systems are case-insensitive: `M8-M.npy` and `m8-m.npy` were once one file.
- **Strings and lists are moved with `SET_STRING_ELT`/`SET_VECTOR_ELT`**, never
  `memcpy`: their elements are R pointers under the write barrier
  (`permute_elements()` in `znp_build.c`).
- **Times: count to double and back is one rule** (`count_to_units()` in
  `znp_time.c`); the writer accepts a value whose count reads back as the same
  double. Change both sides together or what is read stops writing back.
- **Exact or refused.** A value that does not fit its target is an error with
  its index, never rounded or wrapped. `NA` in `logical` or `integer` is refused
  unless `na = "allow"`.
- **Nothing heap-allocated crosses a longjmp.** Results are R vectors allocated
  at their final size and `PROTECT`ed; scratch is `R_alloc()`ed. A zubin builder
  (an external pointer with a finalizer) is for `.npz`, whose size is not known
  up front.
- **C never calls `Rf_error()`.** Statuses come back by enumerator name and
  `R/conditions.R` raises; `zubin_error` from `bin_unpack()` and `bin_pack()` is
  re-raised as the matching `zunpy_` class.
- **Raw DEFLATE is `"deflate-raw"` in zukomp**, not `"deflate"` (which is
  zlib-wrapped). Always pass `max_output` set to the member's declared size.
- **Portable make only** in `src/Makevars`; hand-listed `OBJECTS`; no
  `Makevars.win`. `R_init_zunpy` needs `attribute_visible` under
  `$(C_VISIBILITY)`.

## Naming

<!-- markdownlint-disable MD013 -->
| Layer | Prefix | Examples |
| --- | --- | --- |
| R exports | `npy_` plus `zunpy_info()` | `npy_read()`, `npy_encode()`, `npy_dtype()` |
| R condition classes | `zunpy_` | `zunpy_error`, `zunpy_parse_error`, `zunpy_size_limit` |
| R and C internals | `znp_` / `ZNP_` | `znp_header_check()`, `ZNP_STANDALONE` |
| `.Call` entry points | `zunpy_` | `zunpy_header_check` |
| Test-switching variables | `ZUNPY_` | `ZUNPY_SKIP_HEAVY` |
<!-- markdownlint-enable MD013 -->

## Editing rules

These add to, or deviate from, `.claude/shared/r-package.md`:

- **There is no `README.Rmd`; edit `README.md` directly** and run its example.
- The vignette is `vignettes/zunpy.Rmd`; a chunk that needs a `Suggests` package
  runs only where it is installed.
- Prose is en-GB (`Language: en-GB`, `inst/WORDLIST`). New words go in
  `inst/WORDLIST` through `spelling::update_wordlist()`. `spell_check_setup()`
  sets `Language: en-US`; keep `en-GB`.
- No hard runtime dependency beyond `zukomp` (design D1); add none without a
  recorded decision. `bit64` stays in `Suggests`.
- Every export has `@return` and runnable `@examples`.
- `R/zu_source.R` is copied verbatim from `../zuxml`; fix it there and re-copy.
- `NEWS.md` keeps a versioned heading.
- A change to a dtype mapping updates all three copies of the table (design,
  roxygen, tests) in the same commit.
- Performance claims need evidence from `tools/run-benchmarks`.
- A defect in `zubin`, `zufast` or `zukomp` gets an issue in that repository
  rather than a local workaround.

## Testing

- **Inputs** are bytes from hex or from a fixture. Files only under
  `withr::local_tempdir()`.
- **Assert on condition classes and fields (`offset`, `index`, `dtype`,
  `member`, `limit`)**, through `expect_zunpy_error()`.
- **Serial**: no `Config/testthat/parallel`.
- **The oracle is NumPy, never hand-written expectations.** Fixtures are written
  by `tools/make-fixtures.py` with NumPy pinned (run it with `uv run
  --no-project --with numpy==2.3.3 python tools/make-fixtures.py`), recorded in
  `MANIFEST.tsv` with a SHA-256 and every value (floats as `float.hex()`, which
  R reads exactly), and never regenerated by a test. `tools/check-fixtures` (the
  `conformance` job) regenerates them and checks each MANIFEST row against
  `np.load()`; the R suite checks `npy_decode()` against the same rows. Nothing
  under `tests/` requires Python. Hostile input is hand-built in
  `test-hostile.R`.
- **Helpers** in `tests/testthat/`: `helper-bytes.R` (`bytes()` from hex,
  `npy_header_bytes()`, `npy_dict()`, `check_dict()`, `find_sig()`, `put_le()`),
  `helper-fixtures.R` (`fixture_path()`, `fixture_bytes()`,
  `fixtures_manifest()`, `fixture_expected()`, `fixture_time()`,
  `fixture_records()`, `table_dtypes()`), `helper-expect.R`
  (`expect_zunpy_error()`), `helper-abi.R` (`exported_symbols()`).
- **Guards** each have a `test_that("GUARD name")`, and a gate counts once it
  has been seen to fail.
- **Keep the suite inside the CRAN time budget:** under 15 s. The design and
  roadmap put the 2 GiB and 10^6-member cases behind a `skip_heavy()` on
  `ZUNPY_SKIP_HEAVY`, which `native-checks.yaml` sets for gctorture; as of
  2026-11-14 no `helper-skip.R` or `skip_heavy()` exists in `tests/testthat/`,
  so the variable has no effect.
- **`expect_zunpy_error(expr, class)` asserts each class on its own.**
  `expect_s3_class(e, c(a, b))` passes when `e` inherits *any* of them, which
  made every class assertion vacuous until 2026-11-14 (#25); never pass it
  several classes.
- **The suite runs in a C locale.** Non-ASCII literals in tests are written as
  `\u` escapes.
- `ZUNPY_FORCED_BE` tells `test-info.R` the suite runs in a
  `-DZNP_FORCE_BE_HOST` build.
- A stage is done when its exit criteria pass in CI on all three platforms. Run
  `gctorture(TRUE)` over the code a C change touches.

## Continuous integration

Shared workflows from `pedrobtz/r-actions`. `R-CMD-check.yaml` calls
`r-cmd-check.yml@v1`; the others are pinned to a commit with the tag in a
comment (v1.22.0, fuzz at v1.26.0); Dependabot proposes the bumps. **Deviation
from `ci.md`:** the callers' profile is quick on pull requests and full on
pushes to `main` and under the `full-ci` label, rather than `profile: auto`.
Stage pull requests carry `full-ci`.

- `R-CMD-check.yaml`, `coverage.yaml`, `pkgdown.yaml`.
- `native-checks.yaml`: sanitizers, valgrind, LTO, gctorture (240-minute budget,
  `ZUNPY_SKIP_HEAVY=true`) and a blocking rchk, weekly as well, plus its own
  `forced-big-endian` job: the whole suite built with `-DZNP_FORCE_BE_HOST`, so
  a little-endian runner takes the element-by-element path a big-endian host
  would; `zunpy_info()$fast_path` proves the flag took.
- `hardening.yaml` (own gates, shared `fuzz.yml`): lint, symbols and the
  mutation check; each fuzz target's canary must crash; libFuzzer over the check
  phase (`fuzz/seeds`) and the `.npz` directory check (`fuzz/seeds-zip`), five
  minutes each per push and an hour each nightly.
- `conformance.yaml` (own): `tools/check-fixtures` against NumPy and `np.load()`
  (design §15).

Nothing is vendored, so there is no `vendor.yaml` and no `native-code.md`
import.
