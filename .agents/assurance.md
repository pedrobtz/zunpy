# Assurance

How this package meets `.claude/shared/assurance.md`. CI checks this
file (r-actions `assurance.yml`), so keep the headings and table
columns as they are.

- **Statuses:** a cell is a fact, `gap #<issue>` or `n/a: <reason>`.
- **Written** 2026-11-14 from the code at the merge of #40, by reading
  each test's assertions, not the design's promises.
- **Not a lifecycle package:** nothing zunpy returns outlives its call.
  There is no external pointer, finalizer, ALTREP class or open
  connection in a result; a connection the caller passes is opened and
  closed within the call, or left as the caller gave it. So there is no
  Objects table.

## Kinds

`compiled` `untrusted-input` `spec` `emits`

## Required checks

`Where` names the workflow file under `.github/workflows/` that runs the
check. Add `(own)` when that workflow is the package's own rather than a
call to r-actions.

| Check         | Status | Where              |
| ------------- | ------ | ------------------ |
| sanitizers    | done   | native-checks.yaml |
| valgrind      | done   | native-checks.yaml |
| rchk          | done   | native-checks.yaml |
| gctorture     | done   | native-checks.yaml |
| analyzers     | gap #42 |                    |
| alloc-failure | gap #43 |                    |
| mutation      | gap #44 |                    |
| fuzz          | done   | hardening.yaml     |
| fuzz-reach    | gap #45 |                    |

`mutation` is a gap although `hardening.yaml` runs
`tools/run-mutation-check`: that check mutates only the lines marked
`/* GUARD: */` and fails unless each is load-bearing. It is a gate on the
guards, not mutation testing of the C, which reports the mutants of every
line that no test kills.

## Boundaries

One row per boundary the package crosses. An oracle knows the answer:

- a conformance suite or test vectors;
- a reference implementation;
- a round trip;
- equivalent inputs compared;
- the bytes the other side received.

"No crash" is not an oracle.

<!-- markdownlint-disable MD013 -->
| Boundary                                         | Oracle                                                                                                                                  | Carried by                                                                                                                       |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `.npy` read: plain dtypes, both byte orders      | NumPy 2.3.3: fixtures with every value in `MANIFEST.tsv`, which `np.load()` is checked against                                          | tests/testthat/test-decode.R ("every plain fixture…"); conformance.yaml (own), job `numpy`                                       |
| `.npy` read: `S`, `U`, `V`, `M8`, `m8`           | NumPy 2.3.3 fixtures and their MANIFEST values                                                                                          | tests/testthat/test-text-time.R ("every string, bytes and time fixture…")                                                       |
| `.npy` read: structured dtypes                   | NumPy 2.3.3 fixtures read as data frames, field by field                                                                                | tests/testthat/test-records.R                                                                                                    |
| `.npy` read: C and Fortran order                 | equivalent inputs: one array in both orders reads the same; `order = "file"` keeps the file's                                           | tests/testthat/test-decode.R ("order = 'file' keeps…")                                                                          |
| `.npy` read: fast path and element path          | equivalent builds: the whole suite with the `memcpy` path compiled out; the direct file path against `npy_decode()` of the same bytes   | native-checks.yaml (own), job `forced-big-endian`; tests/testthat/test-read.R ("#25 the direct and general paths…")             |
| `.npy` header: the literal and `descr` grammar   | NumPy's spelling, from the fixtures; libFuzzer with invariants on every accepted plan (size, count, limits, fields, determinism)        | tests/testthat/test-header.R, test-hostile.R; fuzz/fuzz_header.c                                                                 |
| `.npy` header: other writers' spellings          | Python's `ast.literal_eval()` over headers spelled as NumPy does not (key order, quotes, spacing, trailing commas)                      | gap #46                                                                                                                           |
| `.npy` write                                     | NumPy's bytes: each fixture re-encoded byte for byte; `np.load()` reading what R wrote; round trip over 64 generated arrays             | tests/testthat/test-encode.R ("re-encoding a NumPy fixture…", "round trips…"); conformance.yaml (own), job `r-writes`           |
| `.npy` write: strings and times                  | NumPy's bytes for the string and time fixtures; round trip                                                                              | tests/testthat/test-text-time.R ("re-encoding string and time fixtures…", "round trips over generated strings and times")      |
| `.npy` write: data frames as records             | round trip; `np.load()` reading what R wrote                                                                                            | tests/testthat/test-records.R ("data frames round-trip"); conformance.yaml (own), job `r-writes`                                |
| `.npy` write: forged R objects                   | the classed refusal, in R and from the native entry points called directly                                                              | tests/testthat/test-writer-boundary.R                                                                                            |
| `.npy` write: forged R objects, beyond the cases | a fuzz target over the native writers whose oracle is a status or exactly the planned bytes                                            | gap #41                                                                                                                          |
| `.npz` read                                      | NumPy's `savez()` and `savez_compressed()` fixtures read as their member fixtures do; libFuzzer over the directory check with invariants | tests/testthat/test-npz.R ("every .npz fixture…"); fuzz/fuzz_zip.c                                                               |
| `.npz` read: other writers' archives             | archives written by Info-ZIP `zip` and Python's `zipfile` without NumPy (data descriptors, no ZIP64 extra, other flags)                 | gap #47                                                                                                                           |
| `.npz` read: local headers                       | each local header compared with its central entry (flags, method, name)                                                                 | gap #41                                                                                                                          |
| `.npz` write, stored                             | NumPy's bytes: byte-identical to `numpy.savez()`; `np.load()` reading what R wrote                                                      | tests/testthat/test-npz.R ("a list writes as NumPy's savez() writes it"); conformance.yaml (own), job `r-writes`               |
| `.npz` write, compressed                         | round trip; `np.load()` reading what R wrote                                                                                            | tests/testthat/test-npz.R ("compressed archives round-trip…"); conformance.yaml (own), job `r-writes`                           |
| `.npz` member CRC-32                             | NumPy-written archives' CRCs agree; a changed byte is refused                                                                           | tests/testthat/test-npz.R ("a CRC-32 mismatch is refused")                                                                       |
<!-- markdownlint-enable MD013 -->

## Limits

One row per limit the package enforces. "Straddled by" is the test of
`limit - 1`, `limit` and `limit + 1` on every path that reaches it.

<!-- markdownlint-disable MD013 -->
| Limit                                       | Unit                                  | Straddled by                                                                                    |
| ------------------------------------------- | ------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `max_size`, raw input                       | input bytes                           | tests/testthat/test-hostile.R ("GUARD input-size…")                                             |
| `max_size`, path, connection and `.npz`     | file bytes; declared member bytes     | gap #48                                                                                          |
| `max_header`                                | header bytes                          | gap #49                                                                                          |
| `max_dims`                                  | dimensions                            | gap #50                                                                                          |
| `max_fields`                                | fields, subarray elements counted     | tests/testthat/test-hostile.R ("GUARD columns…")                                                |
| `max_members`                               | archive members                       | gap #51                                                                                          |
| literal nesting depth 8                     | nesting levels                        | gap #52                                                                                          |
| write: 1,024 columns                        | data frame columns                    | gap #53                                                                                          |
| write: `npy_shape` 64 dimensions and 2^53   | dimensions; count                     | tests/testthat/test-writer-boundary.R ("#25 npy_shape at its bounds…")                          |
| write: `.npz` member name 65,535 bytes      | UTF-8 bytes of the key and `.npy`     | tests/testthat/test-npz.R ("#25 member names: the 65,535-byte bound…")                          |
| write: header version 1.0 up to 65,535      | header bytes                          | gap #54                                                                                          |
| read: R dimensions and rows at 2^31 - 1     | elements per dimension; records       | gap #55                                                                                          |
| write: ZIP64 at 65,535 members and 4 GiB    | members; bytes                        | gap #56                                                                                          |
<!-- markdownlint-enable MD013 -->
