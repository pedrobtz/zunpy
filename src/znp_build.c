/*
 * znp_build.c -- the build phase (design 4, 6): a checked plan to an R
 * value.
 *
 * Everything allocated here is sized from the plan, whose sizes the check
 * phase has compared with the bytes present (design 12). Values go through
 * zubin's unpack kernels (zubin/layout.h), so the byte order and the
 * exactness rules are zubin's: an i4 of -2^31 is refused unless NA is
 * allowed, and a 64-bit integer that a double cannot hold exactly is
 * refused rather than rounded.
 *
 * Nothing here calls Rf_error(): a refusal comes back as a status name, an
 * element index and a byte offset, and R/decode.R raises it.
 */
#include <limits.h>
#include <string.h>

#include <zubin.h>

#include "znp_check.h"
#include "znp_r.h"

/* Elements converted between interrupt checks. */
#define ZNP_CHUNK ((size_t)1 << 20)

typedef enum {
    ZNP_BUILD_OK = 0,
    ZNP_BUILD_NA,               /* an NA with no place in the target */
    ZNP_BUILD_UNREPRESENTABLE,  /* a value or a dimension R cannot hold */
    ZNP_BUILD_NOT_YET           /* a dtype a later stage reads */
} znp_build_status;

static const char *build_status_name(znp_build_status st)
{
    switch (st) {
    case ZNP_BUILD_OK:              return "ZNP_OK";
    case ZNP_BUILD_NA:              return "ZNP_BUILD_NA";
    case ZNP_BUILD_UNREPRESENTABLE: return "ZNP_BUILD_UNREPRESENTABLE";
    case ZNP_BUILD_NOT_YET:         return "ZNP_BUILD_NOT_YET";
    }
    return "ZNP_ERR_UNKNOWN";
}

typedef struct {
    int order_file;     /* order = "file": no permutation */
    int as_integer64;   /* int64 = "integer64" */
    int na_allow;       /* na = "allow" */
} znp_opts;

typedef struct {
    znp_build_status status;
    size_t           index;     /* 0-based element, in file order */
    int              dim;       /* for a dimension fault, which one */
} znp_build_fault;

/* The zubin field type for a scalar dtype, and the R vector type it fills. */
static int field_for(const znp_dtype *dt, const znp_opts *o, zb_field *f,
                     SEXPTYPE *rtype)
{
    memset(f, 0, sizeof *f);
    f->count = 1;
    f->size = (uint32_t)dt->itemsize;
    f->big_endian = dt->order == '>';
    switch (dt->kind) {
    case 'b': f->type = ZB_BOOL; *rtype = LGLSXP; break;
    case 'i':
        switch (dt->itemsize) {
        case 1: f->type = ZB_I8; *rtype = INTSXP; break;
        case 2: f->type = ZB_I16; *rtype = INTSXP; break;
        case 4: f->type = ZB_I32; *rtype = INTSXP; break;
        default: f->type = ZB_I64; *rtype = REALSXP; break;
        }
        break;
    case 'u':
        switch (dt->itemsize) {
        case 1: f->type = ZB_U8; *rtype = INTSXP; break;
        case 2: f->type = ZB_U16; *rtype = INTSXP; break;
        case 4: f->type = ZB_U32; *rtype = REALSXP; break;
        default: f->type = ZB_U64; *rtype = REALSXP; break;
        }
        break;
    case 'f':
        f->type = dt->itemsize == 2 ? ZB_F16 : dt->itemsize == 4 ? ZB_F32 : ZB_F64;
        *rtype = REALSXP;
        break;
    case 'c':
        /* Two floats, read element by element below. */
        f->type = dt->itemsize == 8 ? ZB_F32 : ZB_F64;
        *rtype = CPLXSXP;
        break;
    default:
        return 0;
    }
    (void)o;
    return 1;
}

/* Converts n elements starting at element `first`, file order, into the
   matching slots of out. */
static zb_status convert(const uint8_t *data, size_t first, size_t n,
                         const znp_dtype *dt, const zb_field *f,
                         const znp_opts *o, SEXP out, size_t *bad)
{
    const uint8_t *base = data + first * dt->itemsize;
    size_t stride = (size_t)dt->itemsize;
    switch (TYPEOF(out)) {
    case LGLSXP:
        return zb_unpack_i32(base, n, stride, f, LOGICAL(out) + first, 1, bad);
    case INTSXP:
        return zb_unpack_i32(base, n, stride, f, INTEGER(out) + first, o->na_allow, bad);
    case CPLXSXP: {
        Rcomplex *d = COMPLEX(out) + first;
        size_t half = stride / 2;
        int be = f->big_endian;
        for (size_t i = 0; i < n; i++) {
            const uint8_t *p = base + i * stride;
            if (f->type == ZB_F32) {
                d[i].r = be ? zb_rd_f32be(p) : zb_rd_f32le(p);
                d[i].i = be ? zb_rd_f32be(p + half) : zb_rd_f32le(p + half);
            } else {
                d[i].r = be ? zb_rd_f64be(p) : zb_rd_f64le(p);
                d[i].i = be ? zb_rd_f64be(p + half) : zb_rd_f64le(p + half);
            }
        }
        return ZB_OK;
    }
    default: /* REALSXP */
        if (f->type == ZB_I64 || f->type == ZB_U64) {
            double *d = REAL(out) + first;
            if (!o->as_integer64)
                return zb_unpack_f64x(base, n, stride, f, d, bad);
            /* integer64 is the int64 bit pattern in a double. */
            int64_t *v = (int64_t *)(void *)d;
            zb_status st = zb_unpack_i64(base, n, stride, f, v, bad);
            if (st == ZB_OK && !o->na_allow) {
                /* -2^63 is bit64's NA_integer64_. */
                for (size_t i = 0; i < n; i++)
                    if (v[i] == INT64_MIN) {
                        *bad = i;
                        return ZB_ERR_NA;
                    }
            }
            return st;
        }
        return zb_unpack_f64(base, n, stride, f, REAL(out) + first);
    }
}

/* A C-order array to R's column-major order, in one pass: dst element t,
   with index (i0, ..., ik-1) and i0 fastest, comes from src element
   sum(i_j * cstride_j), where the last index is fastest. */
static void permute(SEXP src, SEXP dst, const uint64_t *shape, int k)
{
    size_t n = (size_t)XLENGTH(src), width;
    size_t cstride[ZNP_MAX_DIMS_CAP], idx[ZNP_MAX_DIMS_CAP];
    const char *s;
    char *d;
    switch (TYPEOF(src)) {
    case LGLSXP:  s = (const char *)LOGICAL(src); d = (char *)LOGICAL(dst); width = sizeof(int); break;
    case INTSXP:  s = (const char *)INTEGER(src); d = (char *)INTEGER(dst); width = sizeof(int); break;
    case CPLXSXP: s = (const char *)COMPLEX(src); d = (char *)COMPLEX(dst); width = sizeof(Rcomplex); break;
    default:      s = (const char *)REAL(src);    d = (char *)REAL(dst);    width = sizeof(double); break;
    }
    cstride[k - 1] = 1;
    for (int j = k - 2; j >= 0; j--)
        cstride[j] = cstride[j + 1] * (size_t)shape[j + 1];
    memset(idx, 0, sizeof idx);
    size_t from = 0;
    for (size_t t = 0; t < n; t++) {
        if (t % ZNP_CHUNK == ZNP_CHUNK - 1)
            R_CheckUserInterrupt();
        memcpy(d + t * width, s + from * width, width);
        for (int j = 0; j < k; j++) {
            if (++idx[j] < shape[j]) {
                from += cstride[j];
                break;
            }
            idx[j] = 0;
            from -= cstride[j] * ((size_t)shape[j] - 1);
        }
    }
}

static SEXP dim_attr(const uint64_t *shape, int k, int reverse)
{
    SEXP dim = PROTECT(Rf_allocVector(INTSXP, k));
    for (int j = 0; j < k; j++)
        INTEGER(dim)[j] = (int)shape[reverse ? k - 1 - j : j];
    UNPROTECT(1);
    return dim;
}

static SEXP build(const uint8_t *data, const znp_plan *plan, const znp_opts *o,
                  znp_build_fault *fault)
{
    zb_field f;
    SEXPTYPE rtype;
    fault->status = ZNP_BUILD_OK;
    fault->index = 0;
    fault->dim = -1;

    if (plan->structured || !field_for(&plan->dtype, o, &f, &rtype)) {
        fault->status = ZNP_BUILD_NOT_YET;
        return R_NilValue;
    }
    /* R's dim is integer; a vector may be long (design 6.2). */
    if (plan->ndim >= 2)
        for (int j = 0; j < plan->ndim; j++)
            if (plan->shape[j] > INT_MAX) {
                fault->status = ZNP_BUILD_UNREPRESENTABLE;
                fault->dim = j;
                return R_NilValue;
            }
    if (plan->count > (uint64_t)R_XLEN_T_MAX) {
        fault->status = ZNP_BUILD_UNREPRESENTABLE;
        return R_NilValue;
    }

    size_t n = (size_t)plan->count;
    const uint8_t *body = data + plan->data_offset;
    SEXP out = PROTECT(Rf_allocVector(rtype, (R_xlen_t)n));
    for (size_t first = 0; first < n; first += ZNP_CHUNK) {
        size_t m = n - first < ZNP_CHUNK ? n - first : ZNP_CHUNK;
        size_t bad = 0;
        zb_status st = convert(body, first, m, &plan->dtype, &f, o, out, &bad);
        if (st != ZB_OK) {
            fault->status = st == ZB_ERR_RANGE && rtype == INTSXP ? ZNP_BUILD_NA
                          : st == ZB_ERR_NA ? ZNP_BUILD_NA
                          : ZNP_BUILD_UNREPRESENTABLE;
            fault->index = first + bad;
            UNPROTECT(1);
            return R_NilValue;
        }
        R_CheckUserInterrupt();
    }

    int k = plan->ndim;
    if (k >= 2) {
        int c_order = !plan->fortran_order;
        if (c_order && !o->order_file) {
            SEXP perm = PROTECT(Rf_allocVector(rtype, (R_xlen_t)n));
            permute(out, perm, plan->shape, k);
            Rf_setAttrib(perm, R_DimSymbol, dim_attr(plan->shape, k, 0));
            UNPROTECT(2);
            return perm;
        }
        Rf_setAttrib(out, R_DimSymbol, dim_attr(plan->shape, k, c_order));
    }
    UNPROTECT(1);
    return out;
}

/* opts: c(order_file, as_integer64, na_allow). Returns list(status, offset,
   index, value, descr, native_order, align64, dim); status is a check or a
   build status name, and R raises. */
SEXP zunpy_decode(SEXP x, SEXP limits, SEXP opts)
{
    znp_limits lim;
    znp_limits_from_r(limits, &lim);
    znp_opts o;
    o.order_file = INTEGER(opts)[0];
    o.as_integer64 = INTEGER(opts)[1];
    o.na_allow = INTEGER(opts)[2];

    const uint8_t *data = RAW(x);
    size_t size = (size_t)XLENGTH(x);
    znp_plan plan;
    znp_fault cf;
    size_t need = 0;
    znp_status st = znp_check_prefix(data, size, &lim, &plan, &need, &cf);
    if (st == ZNP_OK) {
        void *scratch = R_alloc(need, 8);
        st = znp_check(data, size, &lim, scratch, need, &plan, &cf);
    }

    SEXP out = PROTECT(Rf_allocVector(VECSXP, 8));
    const char *names[] = {"status", "offset", "index", "value", "descr",
                           "native_order", "align64", "dim"};
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, 8));
    for (int i = 0; i < 8; i++)
        SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    Rf_setAttrib(out, R_NamesSymbol, nm);

    if (st != ZNP_OK) {
        SET_VECTOR_ELT(out, 0, Rf_mkString(znp_status_name(st)));
        SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)cf.offset));
        UNPROTECT(2);
        return out;
    }

    SET_VECTOR_ELT(out, 4, znp_descr_sexp(&plan));
    SET_VECTOR_ELT(out, 5, Rf_ScalarLogical(plan.native_order));
    SET_VECTOR_ELT(out, 6, Rf_ScalarLogical(plan.align64));

    znp_build_fault bf;
    SEXP value = PROTECT(build(data, &plan, &o, &bf));
    SET_VECTOR_ELT(out, 0, Rf_mkString(build_status_name(bf.status)));
    if (bf.status != ZNP_BUILD_OK) {
        double off = (double)plan.data_offset + (double)bf.index * (double)plan.itemsize;
        SET_VECTOR_ELT(out, 1, Rf_ScalarReal(bf.dim >= 0 ? (double)plan.header_offset : off));
        SET_VECTOR_ELT(out, 2, Rf_ScalarReal(bf.dim >= 0 ? NA_REAL : (double)bf.index + 1));
        SET_VECTOR_ELT(out, 7, Rf_ScalarInteger(bf.dim >= 0 ? bf.dim + 1 : NA_INTEGER));
    } else
        SET_VECTOR_ELT(out, 3, value);
    UNPROTECT(3);
    return out;
}
