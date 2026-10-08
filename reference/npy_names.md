# The names of the arrays in a `.npz`

Reads the directory of a `.npz` archive, without inflating or decoding
any member. A path, URL or connection is read into memory first, bounded
by `max_size`.

## Usage

``` r
npy_names(x, max_size = 2 * 1024^3, max_members = 10000)
```

## Arguments

- x:

  A raw vector holding a `.npz` file, or a path, URL or connection.

- max_size:

  The largest input accepted, in bytes.

- max_members:

  The most members accepted.

## Value

A character vector: each member's name without its `.npy` suffix, in
archive order, as
[`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md)
names the list it returns.

## Examples

``` r
z <- npy_encode(list(a = 1:3, b = c(x = 0.5)))
npy_names(z)
#> [1] "a" "b"
```
