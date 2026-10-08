/* libFuzzer target: the .npz directory check (src/znp_zip.c), R-free.
 *
 * The first byte chooses the limits; the rest is the input. Besides
 * sanitizer findings, it traps on a broken invariant of an accepted
 * directory: every member's data lies inside the input, the declared
 * sizes sum to at most max_size, the count is at most max_members, a
 * stored member's sizes agree, and relaxing the limits accepts it still.
 *
 * Built with -DZNP_FUZZ_CANARY it traps on any accepted archive, which the
 * seed corpus guarantees: tools/run-fuzz requires that crash first. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "znp_zip.h"

static znp_status run(const uint8_t *data, size_t size, const znp_zip_limits *lim,
                      znp_member **m, uint64_t *n)
{
    znp_fault fault;
    uint64_t count = 0;
    *m = NULL;
    *n = 0;
    znp_status st = znp_zip_count(data, size, lim, &count, &fault);
    if (st != ZNP_OK)
        return st;
    *m = malloc((count ? (size_t)count : 1) * sizeof(znp_member));
    if (*m == NULL)
        return ZNP_ERR_SCRATCH;
    return znp_zip_check(data, size, lim, *m, count, n, &fault);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 1)
        return 0;
    uint8_t o = data[0];
    data++;
    size--;
    znp_zip_limits lim;
    lim.max_size = (o & 1) ? 4096 : UINT64_MAX;
    lim.max_members = (o & 2) ? 2 : 10000;

    znp_member *m;
    uint64_t n;
    znp_status st = run(data, size, &lim, &m, &n);
#ifdef ZNP_FUZZ_CANARY
    if (st == ZNP_OK)
        __builtin_trap();
#endif
    if (st == ZNP_OK) {
        uint64_t total = 0;
        if (n > lim.max_members)
            __builtin_trap();
        for (uint64_t i = 0; i < n; i++) {
            if (m[i].data_offset > size || m[i].csize > size - m[i].data_offset)
                __builtin_trap();
            if (m[i].method == 0 && m[i].csize != m[i].usize)
                __builtin_trap();
            if ((const uint8_t *)m[i].name < data ||
                (const uint8_t *)m[i].name + m[i].name_len > data + size)
                __builtin_trap();
            total += m[i].usize;
            (void)znp_crc32(data + m[i].data_offset, (size_t)m[i].csize);
        }
        if (total > lim.max_size)
            __builtin_trap();
        znp_zip_limits relaxed = {UINT64_MAX, 10000};
        znp_member *m2;
        uint64_t n2;
        if (run(data, size, &relaxed, &m2, &n2) != ZNP_OK || n2 != n)
            __builtin_trap();
        free(m2);
    }
    free(m);
    return 0;
}
