/* Memory order (design 6.4, 8): one pass between NumPy's C order (last
   index fastest) and R's column-major order (first index fastest), with an
   interrupt check every 2^20 elements. Elements are `width` bytes. */
#include <string.h>

#include "znp_r.h"

#define ZNP_CHUNK ((size_t)1 << 20)

/* Walks the column-major index (i0 fastest) over n elements and, for each,
   the C-order index c = sum(i_j * cstride_j). to_r: dst[t] = src[c], a
   C-order array into R's order; else dst[c] = src[t], R's order into C. */
void znp_permute(const void *src, void *dst, size_t width, size_t n,
                 const uint64_t *shape, int k, int to_r)
{
    const char *s = src;
    char *d = dst;
    size_t cstride[ZNP_MAX_DIMS_CAP], idx[ZNP_MAX_DIMS_CAP];
    if (k < 1 || n == 0)
        return;
    cstride[k - 1] = 1;
    for (int j = k - 2; j >= 0; j--)
        cstride[j] = cstride[j + 1] * (size_t)shape[j + 1];
    memset(idx, 0, sizeof idx);
    size_t c = 0;
    for (size_t t = 0; t < n; t++) {
        if (t % ZNP_CHUNK == ZNP_CHUNK - 1)
            R_CheckUserInterrupt();
        if (to_r)
            memcpy(d + t * width, s + c * width, width);
        else
            memcpy(d + c * width, s + t * width, width);
        for (int j = 0; j < k; j++) {
            if (++idx[j] < shape[j]) {
                c += cstride[j];
                break;
            }
            idx[j] = 0;
            c -= cstride[j] * ((size_t)shape[j] - 1);
        }
    }
}
