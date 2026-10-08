# Read the header of a NumPy array

Parses and checks a `.npy` header without reading its data: from a raw
vector that holds at least the header, or from a path, URL or
connection, of which only the header's bytes are read.

## Usage

``` r
npy_header(x, max_header = 10000)
```

## Arguments

- x:

  A raw vector holding a `.npy` file or its first bytes, or a path, URL
  or connection.

- max_header:

  The largest header accepted, in bytes; NumPy's own default.

## Value

A list: `version`, the format version as a string such as `"1.0"`;
`descr`, the dtype as a string such as `"<f8"`, or for a structured
dtype a data frame with columns `name`, `title`, `descr`, `offset` and
`shape`; `fortran_order`; `shape`, a numeric vector, empty for a 0-d
array; `itemsize`, bytes per element; and `data_offset`, where the data
starts.

## Examples

``` r
dict <- "{'descr': '<i4', 'fortran_order': False, 'shape': (3,), }"
pad <- (64 - (10 + nchar(dict) + 1) %% 64) %% 64
header <- c(charToRaw(dict), rep(charToRaw(" "), pad), charToRaw("\n"))
x <- c(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0)),
       as.raw(c(length(header), 0)), header)
npy_header(x)
#> $version
#> [1] "1.0"
#> 
#> $descr
#> [1] "<i4"
#> 
#> $fortran_order
#> [1] FALSE
#> 
#> $shape
#> [1] 3
#> 
#> $itemsize
#> [1] 4
#> 
#> $data_offset
#> [1] 128
#> 
```
