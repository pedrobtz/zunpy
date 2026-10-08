#ifndef ZNP_R_H
#define ZNP_R_H

#define R_NO_REMAP
#include <Rinternals.h>

/* .Call entry points, registered in init.c. */
SEXP zunpy_build_info(void);
SEXP zunpy_header_check(SEXP x, SEXP limits);

#endif /* ZNP_R_H */
