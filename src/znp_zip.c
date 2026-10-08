/*
 * znp_zip.c -- the .npz container (design 10). R-free, like the header
 * check: -DZNP_STANDALONE builds it for fuzz/fuzz_zip.c and fuzz/probe.c.
 *
 * Reading walks the central directory, never the local headers alone, and
 * checks every offset and size against the bytes present before anything
 * is inflated: the member count against max_members, and the sum of the
 * declared uncompressed sizes against max_size. Every security guard is an
 * if-line marked GUARD: name, as in znp_header.c.
 *
 * Writing lays the archive out as numpy.savez() does (NumPy 2.x through
 * Python's zipfile, verified 2026-10-08): a ZIP64 extra in every local
 * header, the date 1980-01-01 00:00, version 4.5, Unix attributes 0600,
 * and ZIP64 records only where a size or an offset needs them.
 */
#include <string.h>

#include <zufast/bits.h>

#include "znp_zip.h"

#define SIG_LOCAL   0x04034b50u
#define SIG_CENTRAL 0x02014b50u
#define SIG_EOCD    0x06054b50u
#define SIG_EOCD64  0x06064b50u
#define SIG_LOC64   0x07064b50u

/* ---- CRC-32 (ISO 3309, the polynomial ZIP uses; D6) --------------------- */

/* Slicing-by-8: eight tables let the loop take eight bytes a step, several
   times faster than one byte a step, with the same result. The tables are
   filled once; filling them twice gives the same values, so a race between
   two threads would be harmless, and R calls this from one thread. */
static uint32_t crc_table[8][256];
static int crc_ready = 0;

static void crc_init(void)
{
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++)
            c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        crc_table[0][i] = c;
    }
    for (uint32_t i = 0; i < 256; i++)
        for (int t = 1; t < 8; t++)
            crc_table[t][i] = (crc_table[t - 1][i] >> 8) ^ crc_table[0][crc_table[t - 1][i] & 0xFF];
    crc_ready = 1;
}

uint32_t znp_crc32(const uint8_t *data, size_t n)
{
    if (!crc_ready)
        crc_init();
    uint32_t c = 0xFFFFFFFFu;
    size_t i = 0;
    for (; i + 8 <= n; i += 8) {
        uint32_t lo = c ^ zuf_load_le32(data + i);
        uint32_t hi = zuf_load_le32(data + i + 4);
        c = crc_table[7][lo & 0xFF] ^ crc_table[6][(lo >> 8) & 0xFF] ^
            crc_table[5][(lo >> 16) & 0xFF] ^ crc_table[4][lo >> 24] ^
            crc_table[3][hi & 0xFF] ^ crc_table[2][(hi >> 8) & 0xFF] ^
            crc_table[1][(hi >> 16) & 0xFF] ^ crc_table[0][hi >> 24];
    }
    for (; i < n; i++)
        c = crc_table[0][(c ^ data[i]) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}

/* ---- reading -------------------------------------------------------------- */

static znp_status zfail(znp_fault *fault, znp_status st, uint64_t offset)
{
    fault->status = st;
    fault->offset = offset;
    return st;
}

static uint16_t rd16(const uint8_t *p) { return zuf_load_le16(p); }
static uint32_t rd32(const uint8_t *p) { return zuf_load_le32(p); }
static uint64_t rd64(const uint8_t *p) { return zuf_load_le64(p); }

/* Finds the end-of-central-directory record, and the ZIP64 one when it is
   there; fills the directory's place and its member count. */
static znp_status find_directory(const uint8_t *data, size_t size,
                                 uint64_t *cd_offset, uint64_t *cd_size,
                                 uint64_t *count, znp_fault *fault)
{
    if (size < 22)
        return zfail(fault, ZNP_ERR_TRUNCATED, size);
    /* The record is 22 bytes plus a comment of at most 65,535. */
    size_t lo = size > 22 + 65535 ? size - 22 - 65535 : 0;
    size_t at = size - 22;
    for (;;) {
        if (rd32(data + at) == SIG_EOCD && (size_t)at + 22 + rd16(data + at + 20) == size)
            break;
        if (at == lo)
            return zfail(fault, ZNP_ERR_ZIP, size);
        at--;
    }
    const uint8_t *e = data + at;
    if (rd16(e + 4) != 0 || rd16(e + 6) != 0 || rd16(e + 8) != rd16(e + 10))
        return zfail(fault, ZNP_ERR_UNSUPPORTED, at);       /* split archives */
    *count = rd16(e + 10);
    *cd_size = rd32(e + 12);
    *cd_offset = rd32(e + 16);

    /* ZIP64: a locator 20 bytes before, pointing at the ZIP64 record. */
    if ((*count == 0xFFFF || *cd_size == 0xFFFFFFFFu || *cd_offset == 0xFFFFFFFFu) &&
        at >= 20 && rd32(data + at - 20) == SIG_LOC64) {
        uint64_t z = rd64(data + at - 20 + 8);
        if (z > (uint64_t)size || (uint64_t)size - z < 56) /* GUARD: zip64-record */
            return zfail(fault, ZNP_ERR_ZIP, at - 20);
        const uint8_t *r = data + z;
        if (rd32(r) != SIG_EOCD64)
            return zfail(fault, ZNP_ERR_ZIP, z);
        *count = rd64(r + 32);
        *cd_size = rd64(r + 40);
        *cd_offset = rd64(r + 48);
    }
    if (*cd_offset > (uint64_t)size || *cd_size > (uint64_t)size - *cd_offset) /* GUARD: directory-bounds */
        return zfail(fault, ZNP_ERR_ZIP, at);
    return ZNP_OK;
}

znp_status znp_zip_count(const uint8_t *data, size_t size,
                         const znp_zip_limits *lim, uint64_t *count,
                         znp_fault *fault)
{
    uint64_t off, len;
    fault->status = ZNP_OK;
    fault->offset = 0;
    if ((uint64_t)size > lim->max_size) /* GUARD: zip-input-size */
        return zfail(fault, ZNP_ERR_SIZE_LIMIT, 0);
    znp_status st = find_directory(data, size, &off, &len, count, fault);
    if (st != ZNP_OK)
        return st;
    if (*count > lim->max_members) /* GUARD: members */
        return zfail(fault, ZNP_ERR_MEMBERS_LIMIT, 0);
    /* Every entry takes at least 46 bytes of the directory. Defence in
       depth: max_members has bounded the count already. */
    if (*count > len / 46)
        return zfail(fault, ZNP_ERR_ZIP, off);
    return ZNP_OK;
}

znp_status znp_zip_check(const uint8_t *data, size_t size,
                         const znp_zip_limits *lim, znp_member *out,
                         uint64_t cap, uint64_t *n_out, znp_fault *fault)
{
    uint64_t off, len, count;
    znp_status st = znp_zip_count(data, size, lim, &count, fault);
    if (st != ZNP_OK)
        return st;
    find_directory(data, size, &off, &len, &count, fault);
    if (count > cap)
        return zfail(fault, ZNP_ERR_SCRATCH, 0);

    uint64_t pos = off, end = off + len, total = 0;
    for (uint64_t i = 0; i < count; i++) {
        /* Defence in depth: the entry's own fields stay inside the
           directory (the count check above makes this rare). */
        if (end - pos < 46)
            return zfail(fault, ZNP_ERR_ZIP, pos);
        const uint8_t *c = data + pos;
        if (rd32(c) != SIG_CENTRAL)
            return zfail(fault, ZNP_ERR_ZIP, pos);
        znp_member *m = &out[i];
        memset(m, 0, sizeof *m);
        m->flags = rd16(c + 8);
        m->method = rd16(c + 10);
        m->crc = rd32(c + 16);
        m->csize = rd32(c + 20);
        m->usize = rd32(c + 24);
        uint64_t nlen = rd16(c + 28), xlen = rd16(c + 30), klen = rd16(c + 32);
        uint64_t local = rd32(c + 42);
        if (end - pos - 46 < nlen + xlen + klen) /* GUARD: entry-names */
            return zfail(fault, ZNP_ERR_ZIP, pos);
        m->name = (const char *)c + 46;
        m->name_len = (size_t)nlen;

        /* ZIP64 extra: the fields that are 0xFFFFFFFF in the entry, in the
           order usize, csize, offset. */
        const uint8_t *x = c + 46 + nlen, *xend = x + xlen;
        while (xend - x >= 4) {
            uint16_t id = rd16(x), sz = rd16(x + 2);
            if ((size_t)(xend - x - 4) < sz)
                return zfail(fault, ZNP_ERR_ZIP, (uint64_t)(x - data));
            if (id == 0x0001) {
                const uint8_t *f = x + 4, *fend = f + sz;
                if (m->usize == 0xFFFFFFFFu) {
                    if (fend - f < 8) return zfail(fault, ZNP_ERR_ZIP, (uint64_t)(f - data));
                    m->usize = rd64(f);
                    f += 8;
                }
                if (m->csize == 0xFFFFFFFFu) {
                    if (fend - f < 8) return zfail(fault, ZNP_ERR_ZIP, (uint64_t)(f - data));
                    m->csize = rd64(f);
                    f += 8;
                }
                if (local == 0xFFFFFFFFu) {
                    if (fend - f < 8) return zfail(fault, ZNP_ERR_ZIP, (uint64_t)(f - data));
                    local = rd64(f);
                }
            }
            x += 4 + sz;
        }

        if (m->flags & 0x0001)
            return zfail(fault, ZNP_ERR_UNSUPPORTED, pos);   /* encrypted */
        if (m->method != 0 && m->method != 8)
            return zfail(fault, ZNP_ERR_UNSUPPORTED, pos);
        if (m->method == 0 && m->csize != m->usize)
            return zfail(fault, ZNP_ERR_ZIP, pos);

        /* The local header, for where the data starts. */
        if (local > (uint64_t)size || (uint64_t)size - local < 30) /* GUARD: local-bounds */
            return zfail(fault, ZNP_ERR_ZIP, pos);
        const uint8_t *l = data + local;
        if (rd32(l) != SIG_LOCAL)
            return zfail(fault, ZNP_ERR_ZIP, local);
        uint64_t data_at = local + 30 + rd16(l + 26) + rd16(l + 28);
        if (data_at > (uint64_t)size || m->csize > (uint64_t)size - data_at) /* GUARD: member-bounds */
            return zfail(fault, ZNP_ERR_ZIP, local);
        m->data_offset = data_at;

        total = total + m->usize < total ? UINT64_MAX : total + m->usize;
        if (total > lim->max_size) /* GUARD: declared-total */
            return zfail(fault, ZNP_ERR_SIZE_LIMIT, pos);
        pos += 46 + nlen + xlen + klen;
    }
    *n_out = count;
    return ZNP_OK;
}

/* ---- writing ------------------------------------------------------------ */

#define ZNP_ZIP_TIME 0x0000u     /* 00:00:00 */
#define ZNP_ZIP_DATE 0x0021u     /* 1980-01-01 */

static void wr16(uint8_t *p, uint16_t v) { zuf_store_le16(p, v); }
static void wr32(uint8_t *p, uint32_t v) { zuf_store_le32(p, v); }
static void wr64(uint8_t *p, uint64_t v) { zuf_store_le64(p, v); }

static int non_ascii(const char *s, size_t n)
{
    for (size_t i = 0; i < n; i++)
        if ((unsigned char)s[i] >= 0x80)
            return 1;
    return 0;
}

/* The bytes of the archive for n members; data may be NULL to measure. */
uint64_t znp_zip_write(const znp_zip_entry *e, size_t n, uint8_t *data)
{
    uint64_t pos = 0;
    uint64_t *offsets = NULL;
    /* Local headers and data. NumPy forces ZIP64 here: sizes 0xFFFFFFFF and
       a 20-byte extra with both sizes. */
    for (size_t i = 0; i < n; i++) {
        if (data) {
            uint8_t *p = data + pos;
            wr32(p, SIG_LOCAL);
            wr16(p + 4, 45);
            wr16(p + 6, non_ascii(e[i].name, e[i].name_len) ? 0x0800 : 0);
            wr16(p + 8, e[i].method);
            wr16(p + 10, ZNP_ZIP_TIME);
            wr16(p + 12, ZNP_ZIP_DATE);
            wr32(p + 14, e[i].crc);
            wr32(p + 18, 0xFFFFFFFFu);
            wr32(p + 22, 0xFFFFFFFFu);
            wr16(p + 26, (uint16_t)e[i].name_len);
            wr16(p + 28, 20);
            memcpy(p + 30, e[i].name, e[i].name_len);
            uint8_t *x = p + 30 + e[i].name_len;
            wr16(x, 0x0001);
            wr16(x + 2, 16);
            wr64(x + 4, e[i].usize);
            wr64(x + 12, e[i].csize);
            if (e[i].csize)
                memcpy(x + 20, e[i].payload, (size_t)e[i].csize);
        }
        pos += 30 + e[i].name_len + 20 + e[i].csize;
    }
    (void)offsets;

    /* The central directory: real sizes, and a ZIP64 extra only for the
       fields that do not fit 32 bits, as zipfile writes it. */
    uint64_t cd_start = pos, local = 0;
    for (size_t i = 0; i < n; i++) {
        int big_u = e[i].usize >= 0xFFFFFFFFu, big_c = e[i].csize >= 0xFFFFFFFFu;
        int big_o = local >= 0xFFFFFFFFu;
        uint16_t xlen = (uint16_t)((big_u + big_c + big_o) * 8);
        if (xlen)
            xlen += 4;
        if (data) {
            uint8_t *p = data + pos;
            wr32(p, SIG_CENTRAL);
            wr16(p + 4, (3u << 8) | 45u);      /* made by: Unix, 4.5 */
            wr16(p + 6, 45);
            wr16(p + 8, non_ascii(e[i].name, e[i].name_len) ? 0x0800 : 0);
            wr16(p + 10, e[i].method);
            wr16(p + 12, ZNP_ZIP_TIME);
            wr16(p + 14, ZNP_ZIP_DATE);
            wr32(p + 16, e[i].crc);
            wr32(p + 20, big_c ? 0xFFFFFFFFu : (uint32_t)e[i].csize);
            wr32(p + 24, big_u ? 0xFFFFFFFFu : (uint32_t)e[i].usize);
            wr16(p + 28, (uint16_t)e[i].name_len);
            wr16(p + 30, xlen);
            wr16(p + 32, 0);
            wr16(p + 34, 0);
            wr16(p + 36, 0);
            wr32(p + 38, 0600u << 16);         /* external: -rw------- */
            wr32(p + 42, big_o ? 0xFFFFFFFFu : (uint32_t)local);
            memcpy(p + 46, e[i].name, e[i].name_len);
            uint8_t *x = p + 46 + e[i].name_len;
            if (xlen) {
                wr16(x, 0x0001);
                wr16(x + 2, (uint16_t)(xlen - 4));
                x += 4;
                if (big_u) { wr64(x, e[i].usize); x += 8; }
                if (big_c) { wr64(x, e[i].csize); x += 8; }
                if (big_o) { wr64(x, local); }
            }
        }
        pos += 46 + e[i].name_len + xlen;
        local += 30 + e[i].name_len + 20 + e[i].csize;
    }
    uint64_t cd_size = pos - cd_start;

    /* ZIP64 end records when a count or an offset does not fit. */
    int zip64 = n >= 0xFFFF || cd_start >= 0xFFFFFFFFu || cd_size >= 0xFFFFFFFFu;
    if (zip64) {
        if (data) {
            uint8_t *p = data + pos;
            wr32(p, SIG_EOCD64);
            wr64(p + 4, 44);
            wr16(p + 12, 45);
            wr16(p + 14, 45);
            wr32(p + 16, 0);
            wr32(p + 20, 0);
            wr64(p + 24, n);
            wr64(p + 32, n);
            wr64(p + 40, cd_size);
            wr64(p + 48, cd_start);
            wr32(p + 56, SIG_LOC64);
            wr32(p + 60, 0);
            wr64(p + 64, pos);
            wr32(p + 72, 1);
        }
        pos += 56 + 20;
    }
    if (data) {
        uint8_t *p = data + pos;
        wr32(p, SIG_EOCD);
        wr16(p + 4, 0);
        wr16(p + 6, 0);
        wr16(p + 8, n >= 0xFFFF ? 0xFFFF : (uint16_t)n);
        wr16(p + 10, n >= 0xFFFF ? 0xFFFF : (uint16_t)n);
        wr32(p + 12, cd_size >= 0xFFFFFFFFu ? 0xFFFFFFFFu : (uint32_t)cd_size);
        wr32(p + 16, cd_start >= 0xFFFFFFFFu ? 0xFFFFFFFFu : (uint32_t)cd_start);
        wr16(p + 20, 0);
    }
    pos += 22;
    return pos;
}
