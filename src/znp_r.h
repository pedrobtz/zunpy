#ifndef ZNP_R_H
#define ZNP_R_H

#define R_NO_REMAP
#include <Rinternals.h>

#include "znp_check.h"

/* Shared glue (znp_r_header.c). */
void znp_limits_from_r(SEXP limits, znp_limits *lim);
SEXP znp_descr_sexp(const znp_plan *plan);

/* .Call entry points, registered in init.c. */
SEXP zunpy_build_info(void);
SEXP zunpy_header_check(SEXP x, SEXP limits);
SEXP zunpy_decode(SEXP x, SEXP limits, SEXP opts);

#endif /* ZNP_R_H */
