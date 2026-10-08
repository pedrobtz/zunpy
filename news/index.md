# Changelog

## zunpy 0.0.0.9000

- [`npy_read()`](https://pedrobtz.github.io/zunpy/reference/npy_read.md)
  and
  [`npy_write()`](https://pedrobtz.github.io/zunpy/reference/npy_write.md)
  read and write `.npy` and `.npz` files at a path, a URL or a
  connection, bounded by `max_size`;
  [`npy_header()`](https://pedrobtz.github.io/zunpy/reference/npy_header.md)
  and
  [`npy_names()`](https://pedrobtz.github.io/zunpy/reference/npy_names.md)
  take them too. Reading and writing a file are within 10% of
  [`readBin()`](https://rdrr.io/r/base/readBin.html) and
  [`writeBin()`](https://rdrr.io/r/base/readBin.html).
- `.npz` archives:
  [`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md)
  reads one as a named list (`names` for some members),
  [`npy_encode()`](https://pedrobtz.github.io/zunpy/reference/npy_encode.md)
  writes a named list as one (`compress` for DEFLATE), and
  [`npy_names()`](https://pedrobtz.github.io/zunpy/reference/npy_names.md)
  lists the members. The directory is checked before any member is read,
  members are inflated no further than their declared size, and every
  member’s CRC-32 is checked.
- Structured dtypes (record arrays) read as data frames, one column per
  field or subarray element, and data frames write as record arrays;
  `dtype` can name the dtype of some columns.
- Strings, dates and times, both ways: `S<n>` and `U<n>` read as UTF-8
  character vectors (`strings = "raw"` and `encoding` for `S<n>`) and
  are written from character vectors and factors; `V<n>` reads as a list
  of raw; `datetime64` and `timedelta64` read as `Date`, `POSIXct` (UTC)
  and `difftime`, or as `integer64` counts, and are written from them.
- [`npy_encode()`](https://pedrobtz.github.io/zunpy/reference/npy_encode.md)
  writes an R vector, matrix or array as a `.npy` file in a raw vector,
  byte-identical to `numpy.save()`; `dtype` narrows exactly or refuses,
  and `order` chooses Fortran or C order.
  [`npy_dtype()`](https://pedrobtz.github.io/zunpy/reference/npy_dtype.md)
  gives the default dtype.
- [`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md)
  reads a `.npy` file held in a raw vector, in either byte order and
  memory order, with the header checked whole before anything is
  allocated.
  [`npy_header()`](https://pedrobtz.github.io/zunpy/reference/npy_header.md)
  reads a header alone.
- The condition classes of
  [`?"zunpy-conditions"`](https://pedrobtz.github.io/zunpy/reference/zunpy-conditions.md)
  and
  [`zunpy_info()`](https://pedrobtz.github.io/zunpy/reference/zunpy_info.md).
