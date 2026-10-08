#' What this build of zunpy is
#'
#' Reports the versions of the provider headers zunpy was compiled against
#' and the host's byte order, for bug reports.
#'
#' @return A list: `version`, zunpy's version; `zubin` and `zufast`, the
#'   versions of their headers compiled in; `host_big_endian`, `TRUE` on a
#'   big-endian host (files are read the same way on either); and
#'   `selftest`, `TRUE` when one call into each provider header gave the
#'   expected answer; and `fast_path`, `TRUE` when little-endian `f8`, `i4`
#'   and `c16` data are copied whole rather than element by element.
#' @export
#' @examples
#' zunpy_info()
zunpy_info <- function() {
  b <- .Call(zunpy_build_info)
  list(
    version = as.character(utils::packageVersion("zunpy")),
    zubin = b[[1]],
    zufast = b[[2]],
    host_big_endian = b[[3]],
    selftest = b[[4]],
    fast_path = b[[5]]
  )
}
