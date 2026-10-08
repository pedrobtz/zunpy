# What this build of zunpy is

Reports the versions of the provider headers zunpy was compiled against
and the host's byte order, for bug reports.

## Usage

``` r
zunpy_info()
```

## Value

A list: `version`, zunpy's version; `zubin` and `zufast`, the versions
of their headers compiled in; `host_big_endian`, `TRUE` on a big-endian
host (files are read the same way on either); and `selftest`, `TRUE`
when one call into each provider header gave the expected answer; and
`fast_path`, `TRUE` when little-endian `f8`, `i4` and `c16` data are
copied whole rather than element by element.

## Examples

``` r
zunpy_info()
#> $version
#> [1] "0.1.0"
#> 
#> $zubin
#> [1] "0.0.0"
#> 
#> $zufast
#> [1] "0.1.0"
#> 
#> $host_big_endian
#> [1] FALSE
#> 
#> $selftest
#> [1] TRUE
#> 
#> $fast_path
#> [1] TRUE
#> 
```
