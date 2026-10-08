# Arrays between R and Python

zunpy reads and writes the files NumPy saves arrays in: `.npy`, one
array, and `.npz`, a ZIP archive of them. Python is not needed on either
side of R; the file is the interface.

``` r

library(zunpy)
```

## Reading and writing

[`npy_write()`](https://pedrobtz.github.io/zunpy/reference/npy_write.md)
and
[`npy_read()`](https://pedrobtz.github.io/zunpy/reference/npy_read.md)
take a path, a connection, or (for reading) a URL.
[`npy_encode()`](https://pedrobtz.github.io/zunpy/reference/npy_encode.md)
and
[`npy_decode()`](https://pedrobtz.github.io/zunpy/reference/npy_decode.md)
do the same with raw vectors.

``` r

f <- tempfile(fileext = ".npy")
x <- matrix(c(1.5, 2, 3, 4, 5, 6), 2)
npy_write(x, f)
identical(npy_read(f), x)
#> [1] TRUE
npy_header(f)
#> $version
#> [1] "1.0"
#> 
#> $descr
#> [1] "<f8"
#> 
#> $fortran_order
#> [1] TRUE
#> 
#> $shape
#> [1] 2 3
#> 
#> $itemsize
#> [1] 8
#> 
#> $data_offset
#> [1] 128
```

What zunpy writes is what `numpy.save()` writes for the same array, byte
for byte, header and padding included, so a file round-trips through
either side unchanged.

## Types

Each NumPy dtype reads as the R type that holds it exactly:

| NumPy | R |
|----|----|
| `b1` | logical |
| `i1`, `u1`, `i2`, `u2`, `i4` | integer |
| `u4`, `f2`, `f4`, `f8` | double |
| `i8`, `u8` | double, or [`bit64::integer64`](https://bit64.r-lib.org/reference/bit64-package.html) |
| `c8`, `c16` | complex |
| `S<n>`, `U<n>` | character (UTF-8) |
| `V<n>` | list of raw vectors |
| `M8[D]` | Date |
| `M8[s]` to `M8[ns]` | POSIXct, in UTC |
| `m8` | difftime |
| structured | data frame |

Writing goes the other way, from the R type: logical to `|b1`, integer
to `<i4`, double to `<f8`, complex to `<c16`, character to `<U<n>`,
`Date` to `<M8[D]`, `POSIXct` to `<M8[us]`. `dtype` chooses another for
one call:

``` r

npy_header(npy_encode(c(1, 2, 3), dtype = "<f4"))$descr
#> [1] "<f4"
npy_header(npy_encode(c("a", "bb"), dtype = "|S"))$descr
#> [1] "|S2"
```

### Exact or refused

A value is converted exactly or not at all. A 64-bit integer beyond 2^53
does not fit a double without rounding, so it is an error unless it is
read as `integer64`:

``` r

big <- npy_encode(bit64::as.integer64("9007199254740993"))
try(npy_decode(big))
#> Error in npy_decode(big) : 
#>   element 1 cannot be held in R: beyond 2^53, or a string with NUL
npy_decode(big, int64 = "integer64")
#> integer64
#> [1] 9007199254740993
```

Narrowing on write refuses what does not fit, naming the element:

``` r

try(npy_encode(c(1, 2, 300), dtype = "|u1"))
#> Error in npy_encode(c(1, 2, 300), dtype = "|u1") : 
#>   element 3 does not fit dtype '|u1'
```

`NA` goes only where the type has a place for it. A double `NA` is a NaN
with R’s own payload, so it survives a round trip; NumPy sees a NaN. An
integer `NA` is the bit pattern of `-2^31`, which is an ordinary value
to NumPy, so writing and reading it needs `na = "allow"`:

``` r

try(npy_encode(c(1L, NA)))
#> Error in npy_encode(c(1L, NA)) : 
#>   element 2 is NA, which dtype '<i4' cannot hold; see `na`
npy_decode(npy_encode(c(1L, NA), na = "allow"), na = "allow")
#> [1]  1 NA
```

## Memory order

NumPy stores arrays in C order (last index fastest) by default; R stores
them in Fortran order (first index fastest). zunpy reads either so that
`a[i, j]` in R is `a[i-1, j-1]` in Python, permuting a C-order file in
one pass. It writes R’s own order, which costs nothing and which NumPy
reads as well; `order = "C"` writes C order for readers that need it.

``` r

npy_header(npy_encode(x))$fortran_order
#> [1] TRUE
npy_header(npy_encode(x, order = "C"))$fortran_order
#> [1] FALSE
```

## Records and archives

A data frame is written as a record array, one field per column, and a
record array is read as a data frame:

``` r

df <- data.frame(id = 1:3, score = c(0.5, NA, 2), name = c("a", "b", "c"))
npy_header(npy_encode(df))$descr
#>    name title descr offset shape
#> 1    id  <NA>   <i4      0      
#> 2 score  <NA>   <f8      4      
#> 3  name  <NA>   <U1     12
str(npy_decode(npy_encode(df)))
#> 'data.frame':    3 obs. of  3 variables:
#>  $ id   : int  1 2 3
#>  $ score: num  0.5 NA 2
#>  $ name : chr  "a" "b" "c"
```

A named list is a `.npz`, stored or compressed.
[`npy_names()`](https://pedrobtz.github.io/zunpy/reference/npy_names.md)
reads the directory alone, and `names` reads only some members:

``` r

z <- tempfile(fileext = ".npz")
npy_write(list(weights = x, meta = df), z, compress = TRUE)
npy_names(z)
#> [1] "weights" "meta"
names(npy_read(z, names = "meta"))
#> [1] "meta"
```

## Files from elsewhere

A NumPy file is untrusted input like any other: the header is a Python
literal that NumPy itself evaluates with care. zunpy parses it with a
grammar that knows strings, numbers, tuples, lists and dicts and nothing
else, checks it whole, and compares the size it declares with the bytes
present before allocating anything. A header claiming an array of 2^80
elements costs nothing:

``` r

hostile <- charToRaw("{'descr': '<f8', 'fortran_order': False, 'shape': (1099511627776, 1099511627776), }")
pad <- (64 - (10 + length(hostile) + 1) %% 64) %% 64
bytes <- c(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0)),
           as.raw(c((length(hostile) + pad + 1) %% 256, (length(hostile) + pad + 1) %/% 256)),
           hostile, rep(charToRaw(" "), pad), charToRaw("\n"))
e <- tryCatch(npy_decode(bytes), zunpy_error = function(e) e)
class(e)
#> [1] "zunpy_size_limit"  "zunpy_limit_error" "zunpy_error"      
#> [4] "error"             "condition"
```

Every error is a classed condition (see
[`?"zunpy-conditions"`](https://pedrobtz.github.io/zunpy/reference/zunpy-conditions.md)),
so code can catch a kind of failure rather than match a message. The
limits — `max_size`, `max_header`, `max_dims`, `max_members` — are
arguments.

## What does not round-trip

Some things R has and NumPy does not, and the reverse:

- `dimnames` and names are dropped; a factor is written as its labels.
- R has no 0-d array: a NumPy scalar array reads as a length-1 vector
  and writes back as shape `(1,)`.
- `raw` writes as `|u1`, which reads back as integer.
- A `POSIXct` keeps its instant; its time zone becomes UTC.
- `M8[ns]` beyond about 104 days from 1970 is more precise than a
  double; `datetime = "integer64"` keeps the count exactly.
- A record field’s title, its padding and a subarray’s shape are not
  kept, and a field’s dtype follows its column’s R type unless `dtype`
  names it.
