/* .Call glue for the check phase: a raw vector in, a list out. Statuses
   come back by name and R/conditions.R raises; nothing here calls
   Rf_error() (design 11). */
#include <stdio.h>
#include <string.h>

#include "znp_check.h"
#include "znp_r.h"

/* The dtype as a descr string, normalised: "<f8", "|S5", "<U3", "<M8[ns]". */
static SEXP descr_string(const znp_dtype *dt)
{
    char buf[48];
    uint64_t w = dt->kind == 'U' ? dt->chars : dt->itemsize;
    snprintf(buf, sizeof buf, "%c%c%llu%s%s%s", dt->order, dt->kind,
             (unsigned long long)w, dt->unit[0] ? "[" : "", dt->unit,
             dt->unit[0] ? "]" : "");
    return Rf_mkCharCE(buf, CE_UTF8);
}

static SEXP dims(const uint64_t *shape, int n)
{
    SEXP out = PROTECT(Rf_allocVector(REALSXP, n));
    for (int i = 0; i < n; i++)
        REAL(out)[i] = (double)shape[i];
    UNPROTECT(1);
    return out;
}

static SEXP fields_list(const znp_plan *plan)
{
    int n = plan->n_fields;
    SEXP name = PROTECT(Rf_allocVector(STRSXP, n));
    SEXP title = PROTECT(Rf_allocVector(STRSXP, n));
    SEXP descr = PROTECT(Rf_allocVector(STRSXP, n));
    SEXP offset = PROTECT(Rf_allocVector(REALSXP, n));
    SEXP shape = PROTECT(Rf_allocVector(VECSXP, n));
    for (int i = 0; i < n; i++) {
        const znp_field *f = &plan->fields[i];
        SET_STRING_ELT(name, i, Rf_mkCharLenCE(f->name, (int)f->name_len, CE_UTF8));
        SET_STRING_ELT(title, i, f->title
            ? Rf_mkCharLenCE(f->title, (int)f->title_len, CE_UTF8) : NA_STRING);
        SET_STRING_ELT(descr, i, descr_string(&f->dtype));
        REAL(offset)[i] = (double)f->offset;
        SET_VECTOR_ELT(shape, i, dims(f->shape, f->ndim));
    }
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 5));
    SET_VECTOR_ELT(out, 0, name);
    SET_VECTOR_ELT(out, 1, title);
    SET_VECTOR_ELT(out, 2, descr);
    SET_VECTOR_ELT(out, 3, offset);
    SET_VECTOR_ELT(out, 4, shape);
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, 5));
    const char *names[] = {"name", "title", "descr", "offset", "shape"};
    for (int i = 0; i < 5; i++)
        SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    Rf_setAttrib(out, R_NamesSymbol, nm);
    UNPROTECT(7);
    return out;
}

/* limits: c(max_size, max_header, max_dims, max_fields), checked in R. */
SEXP zunpy_header_check(SEXP x, SEXP limits)
{
    znp_limits lim;
    lim.max_size = (uint64_t)REAL(limits)[0];
    lim.max_header = (uint64_t)REAL(limits)[1];
    lim.max_dims = (int)REAL(limits)[2];
    lim.max_fields = (int)REAL(limits)[3];

    const uint8_t *data = RAW(x);
    size_t size = (size_t)XLENGTH(x);
    znp_plan plan;
    znp_fault fault;
    size_t need = 0;
    znp_status st = znp_check_prefix(data, size, &lim, &plan, &need, &fault);
    if (st == ZNP_OK) {
        void *scratch = R_alloc(need, 8);
        st = znp_check(data, size, &lim, scratch, need, &plan, &fault);
    }

    const char *names[] = {"status", "offset", "version", "header_length",
                           "data_offset", "fortran_order", "shape", "count",
                           "itemsize", "descr", "fields", "native_order",
                           "align64"};
    int n = st == ZNP_OK ? 13 : 2;
    SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, n));
    for (int i = 0; i < n; i++)
        SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    Rf_setAttrib(out, R_NamesSymbol, nm);
    SET_VECTOR_ELT(out, 0, Rf_mkString(znp_status_name(st)));
    SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)fault.offset));
    if (st != ZNP_OK) {
        UNPROTECT(2);
        return out;
    }
    SEXP version = PROTECT(Rf_allocVector(INTSXP, 2));
    INTEGER(version)[0] = plan.major;
    INTEGER(version)[1] = plan.minor;
    SET_VECTOR_ELT(out, 2, version);
    SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)plan.header_len));
    SET_VECTOR_ELT(out, 4, Rf_ScalarReal((double)plan.data_offset));
    SET_VECTOR_ELT(out, 5, Rf_ScalarLogical(plan.fortran_order));
    SET_VECTOR_ELT(out, 6, dims(plan.shape, plan.ndim));
    SET_VECTOR_ELT(out, 7, Rf_ScalarReal((double)plan.count));
    SET_VECTOR_ELT(out, 8, Rf_ScalarReal((double)plan.itemsize));
    SET_VECTOR_ELT(out, 9, plan.structured ? Rf_ScalarString(NA_STRING)
                                           : Rf_ScalarString(descr_string(&plan.dtype)));
    SET_VECTOR_ELT(out, 10, plan.structured ? fields_list(&plan) : R_NilValue);
    SET_VECTOR_ELT(out, 11, Rf_ScalarLogical(plan.native_order));
    SET_VECTOR_ELT(out, 12, Rf_ScalarLogical(plan.align64));
    UNPROTECT(3);
    return out;
}
