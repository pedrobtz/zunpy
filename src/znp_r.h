#ifndef ZNP_R_H
#define ZNP_R_H

#define R_NO_REMAP
#include <Rinternals.h>

#include "znp_check.h"

/* Shared glue (znp_r_header.c). */
void znp_limits_from_r(SEXP limits, znp_limits *lim);
SEXP znp_descr_sexp(const znp_plan *plan);

/* The data of a logical, integer, double, complex or raw vector, through
   the typed accessors (DATAPTR is not part of R's API). */
static inline void *znp_dataptr(SEXP x)
{
    switch (TYPEOF(x)) {
    case LGLSXP:  return LOGICAL(x);
    case INTSXP:  return INTEGER(x);
    case REALSXP: return REAL(x);
    case CPLXSXP: return COMPLEX(x);
    default:      return RAW(x);
    }
}

/* Memory order (znp_perm.c). */
void znp_permute(const void *src, void *dst, size_t width, size_t n,
                 const uint64_t *shape, int k, int to_r);

/* .Call entry points, registered in init.c. */
SEXP zunpy_build_info(void);
SEXP zunpy_header_check(SEXP x, SEXP limits);
SEXP zunpy_decode(SEXP x, SEXP limits, SEXP opts);
SEXP zunpy_encode(SEXP x, SEXP spec, SEXP shape, SEXP opts);

#endif /* ZNP_R_H */
