# Changelog

## zunpy 0.0.0.9000

- [`npy_encode()`](https://pedrobtz.github.io/zunpy/reference/npy_encode.md)
  writes an R vector, matrix or array as a `.npy` file in a raw vector,
  byte-identical to `numpy.save()`; `dtype` narrows exactly or refuses,
  and `order` chooses Fortran or C order.
  [`npy_dtype()`](https://pedrobtz.github.io/zunpy/reference/npy_dtype.md)
  gives the default dtype.
- [`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md)
  reads a `.npy` file held in a raw vector: every numeric, boolean and
  complex dtype, in either byte order and memory order, with the header
  checked whole before anything is allocated.
- [`npy_header()`](https://pedrobtz.github.io/zunpy/reference/npy_header.md)
  reads a header alone.
- The condition classes of
  [`?"zunpy-conditions"`](https://pedrobtz.github.io/zunpy/reference/zunpy-conditions.md)
  and
  [`zunpy_info()`](https://pedrobtz.github.io/zunpy/reference/zunpy_info.md).
