test_that("zunpy_info() reports the build", {
  i <- zunpy_info()
  expect_named(i, c("version", "zubin", "zufast", "host_big_endian",
                    "selftest", "fast_path"))
  expect_match(i$zubin, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  expect_match(i$zufast, "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  expect_true(package_version(i$zufast) >= "0.1.0")
  expect_type(i$host_big_endian, "logical")
  expect_true(i$selftest)
  # The fast path is on exactly when the host is little-endian, unless the
  # build forces the element-by-element path (ZUNPY_FORCED_BE in CI).
  forced <- nzchar(Sys.getenv("ZUNPY_FORCED_BE"))
  expect_identical(i$fast_path, !i$host_big_endian && !forced)
})

test_that("the shared object exports exactly R_init_zunpy", {
  skip_on_cran()
  skip_on_os("windows")
  # covr links the gcov runtime into the shared object, which exports its
  # own symbols.
  skip_if(nzchar(Sys.getenv("R_COVR")), "coverage build")
  skip_if(!nzchar(Sys.which("nm")), "nm not available")
  syms <- exported_symbols(getLoadedDLLs()[["zunpy"]][["path"]])
  skip_if(is.null(syms))
  skip_if(any(grepl("gcov|llvm_prf|llvm_profile", syms)), "instrumented build")
  expect_identical(syms, "R_init_zunpy")
})
