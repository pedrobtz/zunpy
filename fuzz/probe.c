/* The check phase from the command line, for tools/run-mutation-check:
 *
 *     probe FILE MAX_SIZE MAX_HEADER MAX_DIMS MAX_FIELDS [MAX_MEMBERS]
 *
 * prints the status name. A file starting "PK" is checked as a .npz
 * directory, with MAX_SIZE and MAX_MEMBERS. R-free, built with
 * -DZNP_STANDALONE. */
#include <stdio.h>
#include <stdlib.h>

#include "znp_check.h"
#include "znp_zip.h"

int main(int argc, char **argv)
{
    if (argc != 6 && argc != 7) {
        fprintf(stderr, "usage: probe FILE MAX_SIZE MAX_HEADER MAX_DIMS MAX_FIELDS [MAX_MEMBERS]\n");
        return 2;
    }
    FILE *fp = fopen(argv[1], "rb");
    if (fp == NULL)
        return 2;
    /* Exactly the file's bytes on the heap, so that a read past the end is
       one AddressSanitizer reports (run-mutation-check builds with it). */
    static unsigned char tmp[1 << 20];
    size_t n = fread(tmp, 1, sizeof tmp, fp);
    fclose(fp);
    unsigned char *buf = malloc(n ? n : 1);
    if (buf == NULL)
        return 2;
    for (size_t i = 0; i < n; i++)
        buf[i] = tmp[i];

    znp_limits lim;
    lim.max_size = strtoull(argv[2], NULL, 10);
    lim.max_header = strtoull(argv[3], NULL, 10);
    lim.max_dims = atoi(argv[4]);
    lim.max_fields = atoi(argv[5]);
    lim.header_only = 0;

    if (n >= 2 && buf[0] == 'P' && buf[1] == 'K') {
        znp_zip_limits zl;
        zl.max_size = lim.max_size;
        zl.max_members = argc == 7 ? strtoull(argv[6], NULL, 10) : 10000;
        znp_fault zf;
        uint64_t count = 0, got = 0;
        znp_status zs = znp_zip_count(buf, n, &zl, &count, &zf);
        if (zs == ZNP_OK) {
            znp_member *m = malloc((count ? (size_t)count : 1) * sizeof *m);
            zs = znp_zip_check(buf, n, &zl, m, count, &got, &zf);
            free(m);
        }
        printf("%s\n", znp_status_name(zs));
        return 0;
    }

    znp_plan plan;
    znp_fault fault;
    size_t need;
    znp_status st = znp_check_prefix(buf, n, &lim, &plan, &need, &fault);
    if (st == ZNP_OK) {
        void *scratch = malloc(need ? need : 1);
        st = znp_check(buf, n, &lim, scratch, need, &plan, &fault);
        free(scratch);
    }
    printf("%s\n", znp_status_name(st));
    return 0;
}
