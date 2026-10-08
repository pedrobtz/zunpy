/* The check phase from the command line, for tools/run-mutation-check:
 *
 *     probe FILE MAX_SIZE MAX_HEADER MAX_DIMS MAX_FIELDS
 *
 * prints the status name. R-free, built with -DZNP_STANDALONE. */
#include <stdio.h>
#include <stdlib.h>

#include "znp_check.h"

int main(int argc, char **argv)
{
    if (argc != 6) {
        fprintf(stderr, "usage: probe FILE MAX_SIZE MAX_HEADER MAX_DIMS MAX_FIELDS\n");
        return 2;
    }
    FILE *fp = fopen(argv[1], "rb");
    if (fp == NULL)
        return 2;
    static unsigned char buf[1 << 20];
    size_t n = fread(buf, 1, sizeof buf, fp);
    fclose(fp);

    znp_limits lim;
    lim.max_size = strtoull(argv[2], NULL, 10);
    lim.max_header = strtoull(argv[3], NULL, 10);
    lim.max_dims = atoi(argv[4]);
    lim.max_fields = atoi(argv[5]);
    lim.header_only = 0;

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
