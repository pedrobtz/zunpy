# Conditions raised by zunpy

Every error zunpy raises carries a condition class, so it can be caught
by kind rather than by matching the message, which may change. Every
class below inherits from `zunpy_error`. Offsets are 0-based byte
offsets into the input; in a `.npz` they count from the start of the
member, and `member` names it.

## Details

- `zunpy_invalid_argument`:

  An argument was unusable, including a `dtype` the value cannot reach.
  Carries `arg`.

- `zunpy_parse_error`:

  The input is not a `.npy` or `.npz`: a bad magic string, version,
  header grammar or `descr`, or truncated or trailing data. Carries
  `offset`.

- `zunpy_invalid_error`:

  The input is well formed but inconsistent: record fields overlap or
  share a name, a string is not valid in its encoding (a surrogate in
  `U`, bytes that are not UTF-8 in `S`), or a checksum does not match.
  Carries `offset`, and `index` for a value.

- `zunpy_unsupported_type`:

  A dtype or an R value with no counterpart: object arrays, long
  doubles, nested structured dtypes. Carries `dtype`.

- `zunpy_unrepresentable`:

  A value R cannot hold: a dimension above `2^31 - 1`, or a 64-bit
  integer beyond `2^53` read as a double. Carries `offset` and `index`.

- `zunpy_na_error`:

  An `NA` with no representation in the target. Carries `index`.

- `zunpy_range_error`:

  A value does not fit the requested dtype. Carries `index`.

- `zunpy_limit_error`:

  A limit was reached. Carries `limit`, the argument's name, and
  `limit_value`. Its subclasses are `zunpy_size_limit`,
  `zunpy_header_limit`, `zunpy_dims_limit` and `zunpy_members_limit`.

- `zunpy_io_error`:

  A file or connection could not be read or written.

Warnings inherit from `zunpy_warning`: `zunpy_byte_order` when a dtype
gives its byte order as native (`=`) or not at all, which NumPy never
writes and which is read as little-endian; and `zunpy_alignment` when
the data starts at a multiple of 16 bytes but not of 64, as files from
NumPy before 1.14 and from other writers do.

## Examples

``` r
e <- tryCatch(
  stop(structure(
    class = c("zunpy_parse_error", "zunpy_error", "error", "condition"),
    list(message = "not a .npy file", call = NULL, offset = 0)
  )),
  zunpy_error = function(e) e
)
class(e)
#> [1] "zunpy_parse_error" "zunpy_error"       "error"            
#> [4] "condition"        
e$offset
#> [1] 0
```
