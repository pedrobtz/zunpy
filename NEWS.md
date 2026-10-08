# zunpy 0.0.0.9000

* Strings, dates and times, both ways: `S<n>` and `U<n>` read as UTF-8
  character vectors (`strings = "raw"` and `encoding` for `S<n>`) and are
  written from character vectors and factors; `V<n>` reads as a list of raw;
  `datetime64` and `timedelta64` read as `Date`, `POSIXct` (UTC) and
  `difftime`, or as `integer64` counts, and are written from them.
* `npy_encode()` writes an R vector, matrix or array as a `.npy` file in a
  raw vector, byte-identical to `numpy.save()`; `dtype` narrows exactly or
  refuses, and `order` chooses Fortran or C order. `npy_dtype()` gives the
  default dtype.
* `npy_decode()` reads a `.npy` file held in a raw vector, in either byte
  order and memory order, with the header checked whole before anything is
  allocated. `npy_header()` reads a header alone.
* The condition classes of `?"zunpy-conditions"` and `zunpy_info()`.
