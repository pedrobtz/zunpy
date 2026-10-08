/* libFuzzer target: the check phase (src/znp_header.c), R-free.
 *
 * The first byte chooses the limits; the rest is the input. Besides
 * sanitizer findings, it traps on a broken invariant of an accepted plan:
 *   the declared data ends exactly at the end of the input;
 *   count is the product of the shape, and data_bytes count * itemsize;
 *   the limits hold (dimensions, fields);
 *   every field lies inside the record, with a NUL-terminated UTF-8 name;
 *   the same input gives the same answer twice;
 *   relaxing every limit can only accept more, never less.
 *
 * Built with -DZNP_FUZZ_CANARY it traps as soon as any input is accepted,
 * which the seed corpus guarantees: tools/run-fuzz requires that crash
 * before it trusts this target. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <zufast/utf8.h>

#include "znp_check.h"

static znp_status run(const uint8_t *data, size_t size, const znp_limits *lim,
                      znp_plan *plan, void **scratch)
{
    znp_fault fault;
    size_t need;
    *scratch = NULL;
    znp_status st = znp_check_prefix(data, size, lim, plan, &need, &fault);
    if (st != ZNP_OK)
        return st;
    *scratch = malloc(need ? need : 1);
    if (*scratch == NULL)
        return ZNP_ERR_SCRATCH;
    return znp_check(data, size, lim, *scratch, need, plan, &fault);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 1)
        return 0;
    uint8_t o = data[0];
    data++;
    size--;

    znp_limits lim;
    lim.max_size = (o & 1) ? 1u << 20 : UINT64_MAX;
    lim.max_header = (o & 2) ? 256 : 1u << 20;
    lim.max_dims = (o >> 2) & 7 ? ((o >> 2) & 7) * 8 : 1;   /* 1, 8 .. 56 */
    lim.max_fields = (o & 0x20) ? 4 : 1024;
    lim.header_only = 0;

    znp_plan plan;
    void *scratch;
    znp_status st = run(data, size, &lim, &plan, &scratch);

#ifdef ZNP_FUZZ_CANARY
    if (st == ZNP_OK)
        __builtin_trap();
#endif

    if (st == ZNP_OK) {
        if (plan.data_offset + plan.data_bytes != size)
            __builtin_trap();
        if (plan.ndim < 0 || plan.ndim > lim.max_dims)
            __builtin_trap();
        uint64_t count = 1;
        for (int d = 0; d < plan.ndim; d++) {
            if (plan.shape[d] != 0 && count > UINT64_MAX / plan.shape[d])
                count = UINT64_MAX;
            else
                count *= plan.shape[d];
        }
        if (count != plan.count)
            __builtin_trap();
        if (plan.itemsize != 0 && plan.data_bytes / plan.itemsize != plan.count)
            __builtin_trap();
        if (plan.n_fields < 0 || plan.n_fields > lim.max_fields)
            __builtin_trap();
        if (plan.itemsize > lim.max_size)
            __builtin_trap();
        uint64_t columns = 0;
        for (int i = 0; i < plan.n_fields; i++) {
            uint64_t m = 1;
            for (int d = 0; d < plan.fields[i].ndim; d++)
                m *= plan.fields[i].shape[d];
            columns += m;
        }
        if (columns > (uint64_t)lim.max_fields)
            __builtin_trap();
        if (!plan.structured && plan.n_fields != 0)
            __builtin_trap();
        for (int i = 0; i < plan.n_fields; i++) {
            const znp_field *f = &plan.fields[i];
            if (f->offset > plan.itemsize || f->size > plan.itemsize - f->offset)
                __builtin_trap();
            if (f->name == NULL || strlen(f->name) != f->name_len ||
                !zuf_utf8_valid(f->name, f->name_len))
                __builtin_trap();
        }
        znp_limits relaxed = {UINT64_MAX, 1u << 20, ZNP_MAX_DIMS_CAP, 1 << 20, 0};
        znp_plan again;
        void *scratch2;
        if (run(data, size, &relaxed, &again, &scratch2) != ZNP_OK ||
            again.count != plan.count || again.itemsize != plan.itemsize)
            __builtin_trap();
        free(scratch2);
    }
    znp_plan twice;
    void *scratch3;
    if (run(data, size, &lim, &twice, &scratch3) != st)
        __builtin_trap();
    free(scratch3);
    free(scratch);
    return 0;
}
