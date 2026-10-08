## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

* GitHub Actions (`pedrobtz/r-actions`): macOS (R release), Windows (R
  release), Ubuntu (R release and oldrel-1).
* Containers matching CRAN's r-devel-linux-x86_64-debian-gcc (GCC 16) and
  -debian-clang (clang 23) flavours.
* Native-code checks on every change: ASan and UBSan, valgrind, gctorture,
  rchk and LTO, and the whole test suite with the little-endian fast path
  compiled out, as a big-endian host would run it.

## Dependencies

zunpy links to the C headers of zubin and zufast (`LinkingTo`) and calls
zukomp for DEFLATE; all three are by the same maintainer and were accepted
on CRAN before this submission. Nothing is vendored.

## Python

zunpy reads and writes NumPy's file formats without Python. The tests use
committed files written by NumPy 2.3.3; no test, example or vignette runs
Python.
