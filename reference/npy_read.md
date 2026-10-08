# Read a NumPy file

Reads a `.npy` or `.npz` file from a path, a URL or a connection, and
decodes it as
[`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md)
does.

## Usage

``` r
npy_read(file, ..., names = NULL, max_size = 2 * 1024^3)
```

## Arguments

- file:

  A path, a URL (`http://`, `https://`, `ftp://`, `ftps://` or
  `file://`), or a connection.

- ...:

  Further arguments of
  [`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md):
  `order`, `int64`, `na`, `strings`, `encoding`, `datetime`,
  `max_header`, `max_dims` and `max_members`.

- names:

  For a `.npz`, the members to read (by default all of them).

- max_size:

  The largest input accepted, in bytes.

## Value

As
[`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md).

## Details

The input is read whole into memory first, never more than `max_size`
bytes of it: a path whose size is above `max_size` is refused before it
is opened, and a URL or connection is read no further than one byte past
it. For a `.npz`, `names` decodes and inflates only the members named.

A connection that is not open is opened in binary mode and closed again;
an open one must be binary, is read from its current position, and is
left open.

## See also

[`npy_write()`](https://pedrobtz.github.io/zunpy/reference/npy_write.md);
[`npy_header()`](https://pedrobtz.github.io/zunpy/reference/npy_header.md)
and
[`npy_names()`](https://pedrobtz.github.io/zunpy/reference/npy_names.md)
read only the header or the directory.

## Examples

``` r
f <- tempfile(fileext = ".npy")
npy_write(matrix(1:6, 2), f)
npy_read(f)
#>      [,1] [,2] [,3]
#> [1,]    1    3    5
#> [2,]    2    4    6
unlink(f)
```
