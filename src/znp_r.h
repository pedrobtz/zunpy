#ifndef ZNP_R_H
#define ZNP_R_H

#define R_NO_REMAP
#include <Rinternals.h>

#include "znp_check.h"

/* Shared glue (znp_r_header.c). */
void znp_limits_from_r(SEXP limits, znp_limits *lim);
SEXP znp_descr_sexp(const znp_plan *plan);
SEXP znp_dtype_sexp(const znp_dtype *dt);

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

/* Text and bytes (znp_text.c). */
SEXP znp_read_bytes(const uint8_t *base, size_t n, size_t stride, size_t width,
                    int strip);
SEXP znp_read_s(const uint8_t *base, size_t n, size_t stride, size_t width,
                int encoding, int *status, size_t *bad);
SEXP znp_read_u(const uint8_t *base, size_t n, size_t stride, size_t chars,
                int big_endian, int *status, size_t *bad);
size_t znp_text_width(SEXP x, int as_u);
int znp_write_text(SEXP x, uint8_t *dst, size_t stride, size_t width, int as_u,
                   size_t *bad);

/* datetime64 and timedelta64 counts (znp_time.c). */
int znp_read_counts(const uint8_t *base, size_t n, size_t stride, int big_endian,
                    int64_t scale, double *dst, size_t *bad);
int znp_write_counts(const double *x, size_t n, int64_t scale, uint8_t *dst,
                     size_t stride, size_t *bad);

/* Ticks per R unit for a datetime64 or timedelta64 unit, or 0 when the
   unit has no R class and the counts are returned as integer64 (design
   6.1): M8[D] is days (Date), M8[s..ns] seconds (POSIXct); m8 adds mins,
   hours and weeks, which difftime has. */
int64_t znp_time_scale(char kind, const char *unit);

/* Memory order (znp_perm.c). */
void znp_permute(const void *src, void *dst, size_t width, size_t n,
                 const uint64_t *shape, int k, int to_r);

/* .Call entry points, registered in init.c. */
SEXP zunpy_build_info(void);
SEXP zunpy_header_check(SEXP x, SEXP limits);
SEXP zunpy_decode(SEXP x, SEXP limits, SEXP opts);
SEXP zunpy_encode(SEXP x, SEXP spec, SEXP shape, SEXP opts);
SEXP zunpy_encode_records(SEXP cols, SEXP specs, SEXP names, SEXP shape,
                          SEXP opts, SEXP int64s);

#endif /* ZNP_R_H */
