/*
 * znp_zip.h -- the .npz container's R-free interface (design 10).
 *
 * Reading is two calls, as the header check is: znp_zip_count() finds the
 * directory and bounds the member count by max_members and by the
 * directory's size; the caller allocates that many znp_member and
 * znp_zip_check() fills them, every offset and size checked against the
 * bytes present and the declared total against max_size.
 */
#ifndef ZNP_ZIP_H
#define ZNP_ZIP_H

#include <stddef.h>
#include <stdint.h>

#include "znp_check.h"

typedef struct {
    uint64_t max_size;      /* bytes: the archive, and its members' total */
    uint64_t max_members;
} znp_zip_limits;

typedef struct {
    const char *name;       /* in the input, not NUL-terminated */
    size_t      name_len;
    uint16_t    flags;
    uint16_t    method;     /* 0 stored, 8 DEFLATE */
    uint32_t    crc;
    uint64_t    csize, usize;
    uint64_t    data_offset;
} znp_member;

znp_status znp_zip_count(const uint8_t *data, size_t size,
                         const znp_zip_limits *lim, uint64_t *count,
                         znp_fault *fault);
znp_status znp_zip_check(const uint8_t *data, size_t size,
                         const znp_zip_limits *lim, znp_member *out,
                         uint64_t cap, uint64_t *n, znp_fault *fault);

uint32_t znp_crc32(const uint8_t *data, size_t n);

/* One member to write: its name (UTF-8), method, the CRC-32 and size of its
   uncompressed bytes, and the bytes as stored (compressed or not). */
typedef struct {
    const char    *name;
    size_t         name_len;
    uint16_t       method;
    uint32_t       crc;
    uint64_t       usize, csize;
    const uint8_t *payload;
} znp_zip_entry;

/* Writes the archive into data, or with data NULL returns its size. */
uint64_t znp_zip_write(const znp_zip_entry *e, size_t n, uint8_t *data);

#endif /* ZNP_ZIP_H */
