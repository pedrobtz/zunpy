/*
 * znp_header.c -- the check phase (design 4, 9, 12). R-free.
 *
 * Three steps, each finished before the next begins:
 *
 *   1. the prefix (9.1): magic, version, header length, alignment, limits;
 *   2. the literal (9.2): the dict parsed into a small tree of nodes held in
 *      the caller's scratch, by a recursive descent with a depth cap;
 *   3. the meaning: exactly the keys descr, fortran_order and shape; the
 *      descr strings (9.3), a structured list or dict; the shape; and the
 *      declared size against the bytes present.
 *
 * The parser is a grammar, not an evaluator (D12): it knows strings, ints,
 * True, False, None, tuples, lists and dicts, and nothing else.
 *
 * Every security guard is an if-line marked GUARD: name in a comment;
 * tools/run-mutation-check disables each in turn and requires its hostile
 * input (fuzz/probe.c) to change outcome.
 */
#include <stdlib.h>
#include <string.h>

#include <zufast/bits.h>
#include <zufast/number.h>
#include <zufast/utf8.h>

#include "znp_check.h"

const char *znp_status_name(znp_status st)
{
    switch (st) {
    case ZNP_OK:               return "ZNP_OK";
    case ZNP_ERR_MAGIC:        return "ZNP_ERR_MAGIC";
    case ZNP_ERR_VERSION:      return "ZNP_ERR_VERSION";
    case ZNP_ERR_TRUNCATED:    return "ZNP_ERR_TRUNCATED";
    case ZNP_ERR_TRAILING:     return "ZNP_ERR_TRAILING";
    case ZNP_ERR_ALIGN:        return "ZNP_ERR_ALIGN";
    case ZNP_ERR_ENCODING:     return "ZNP_ERR_ENCODING";
    case ZNP_ERR_SYNTAX:       return "ZNP_ERR_SYNTAX";
    case ZNP_ERR_DEPTH:        return "ZNP_ERR_DEPTH";
    case ZNP_ERR_KEY:          return "ZNP_ERR_KEY";
    case ZNP_ERR_TYPE:         return "ZNP_ERR_TYPE";
    case ZNP_ERR_DESCR:        return "ZNP_ERR_DESCR";
    case ZNP_ERR_SHAPE:        return "ZNP_ERR_SHAPE";
    case ZNP_ERR_LAYOUT:       return "ZNP_ERR_LAYOUT";
    case ZNP_ERR_UNSUPPORTED:  return "ZNP_ERR_UNSUPPORTED";
    case ZNP_ERR_SIZE_LIMIT:   return "ZNP_ERR_SIZE_LIMIT";
    case ZNP_ERR_HEADER_LIMIT: return "ZNP_ERR_HEADER_LIMIT";
    case ZNP_ERR_DIMS_LIMIT:   return "ZNP_ERR_DIMS_LIMIT";
    case ZNP_ERR_FIELDS_LIMIT: return "ZNP_ERR_FIELDS_LIMIT";
    case ZNP_ERR_SCRATCH:      return "ZNP_ERR_SCRATCH";
    }
    return "ZNP_ERR_UNKNOWN";
}

static const uint8_t znp_magic[6] = {0x93, 'N', 'U', 'M', 'P', 'Y'};

/* ---- saturating arithmetic --------------------------------------------- */

static uint64_t sat_mul(uint64_t a, uint64_t b)
{
    if (a != 0 && b > UINT64_MAX / a)
        return UINT64_MAX;
    return a * b;
}

static uint64_t sat_add(uint64_t a, uint64_t b)
{
    return (b > UINT64_MAX - a) ? UINT64_MAX : a + b;
}

/* ---- the scratch -------------------------------------------------------- */

/* A literal value. Children of a tuple, list or dict are a linked list in
   source order; a dict's children alternate key, value. */
enum { N_STR, N_INT, N_BIGINT, N_BOOL, N_NONE, N_TUPLE, N_LIST, N_DICT };

typedef struct {
    uint8_t  type;
    uint32_t pos;       /* offset in the header of the value's first byte */
    uint32_t n;         /* children */
    uint32_t child;     /* first child, or UINT32_MAX */
    uint32_t next;      /* next sibling, or UINT32_MAX */
    uint32_t str;       /* N_STR: offset of the decoded text in strbuf */
    uint32_t len;       /* N_STR: its length in bytes */
    int64_t  i;         /* N_INT, N_BOOL */
} znp_node;

#define NIL UINT32_MAX

/* The scratch is carved into nodes, fields, a sort array and the string
   buffer. Every count is bounded by the header length, which the prefix has
   bounded by max_header and by the bytes present: each node consumes at
   least one byte of the header, and a decoded string at most two bytes per
   byte of source plus its NUL. */
typedef struct {
    size_t n_nodes, n_fields, n_str;
    size_t off_fields, off_sort, off_str, total;
} znp_layout;

typedef struct { uint64_t off, size; } znp_span;

static size_t align8(size_t x) { return (x + 7u) & ~(size_t)7u; }

static int scratch_layout(uint64_t header_len, const znp_limits *lim, znp_layout *L)
{
    /* header_len is at most max_header and at most the input size, so the
       products below fit size_t whenever the input itself does. */
    L->n_nodes = (size_t)header_len + 1;
    L->n_fields = (size_t)header_len + 1;
    if (lim->max_fields > 0 && (size_t)lim->max_fields < L->n_fields)
        L->n_fields = (size_t)lim->max_fields;
    /* 2 bytes per source byte, a NUL per string, and room for generated
       names (f<index>) of fields declared with an empty name. */
    L->n_str = 3 * (size_t)header_len + 24 * L->n_fields + 16;
    L->off_fields = align8(L->n_nodes * sizeof(znp_node));
    L->off_sort = align8(L->off_fields + L->n_fields * sizeof(znp_field));
    L->off_str = align8(L->off_sort + L->n_fields * sizeof(znp_span));
    L->total = L->off_str + L->n_str;
    return 0;
}

/* ---- step 1: the prefix ------------------------------------------------- */

static znp_status fail(znp_fault *fault, znp_status st, uint64_t offset)
{
    fault->status = st;
    fault->offset = offset;
    return st;
}

znp_status znp_check_prefix(const uint8_t *data, size_t size,
                            const znp_limits *lim, znp_plan *plan,
                            size_t *scratch_size, znp_fault *fault)
{
    memset(plan, 0, sizeof *plan);
    *scratch_size = 0;
    fault->status = ZNP_OK;
    fault->offset = 0;

    if ((uint64_t)size > lim->max_size) /* GUARD: input-size */
        return fail(fault, ZNP_ERR_SIZE_LIMIT, 0);

    size_t m = size < 6 ? size : 6;
    for (size_t i = 0; i < m; i++)
        if (data[i] != znp_magic[i])
            return fail(fault, ZNP_ERR_MAGIC, i);
    if (size < 8)
        return fail(fault, ZNP_ERR_TRUNCATED, size);

    plan->major = data[6];
    plan->minor = data[7];
    if (plan->major < 1 || plan->major > 3)
        return fail(fault, ZNP_ERR_VERSION, 6);
    if (plan->minor != 0)
        return fail(fault, ZNP_ERR_VERSION, 7);

    plan->header_offset = plan->major == 1 ? 10 : 12;
    if (size < plan->header_offset)
        return fail(fault, ZNP_ERR_TRUNCATED, size);
    plan->header_len = plan->major == 1 ? zuf_load_le16(data + 8)
                                        : zuf_load_le32(data + 8);

    if (plan->header_len > lim->max_header) /* GUARD: header-limit */
        return fail(fault, ZNP_ERR_HEADER_LIMIT, 8);
    plan->data_offset = plan->header_offset + plan->header_len;
    if (plan->data_offset > (uint64_t)size) /* GUARD: header-truncated */
        return fail(fault, ZNP_ERR_TRUNCATED, size);
    /* D8: NumPy aligns to 64 since 1.14 and to 16 before; any other offset
       is refused, and 16 without 64 is reported for a warning. */
    if (plan->data_offset % 16 != 0)
        return fail(fault, ZNP_ERR_ALIGN, 8);
    plan->align64 = plan->data_offset % 64 == 0;

    znp_layout L;
    scratch_layout(plan->header_len, lim, &L);
    *scratch_size = L.total;
    return ZNP_OK;
}

/* ---- step 2: the literal ------------------------------------------------ */

typedef struct {
    const uint8_t *h;       /* the header dict */
    size_t         n;       /* its length */
    size_t         pos;
    int            utf8;    /* version 3: UTF-8; else Latin-1 */
    znp_node      *nodes;
    size_t         n_nodes, used_nodes;
    char          *str;
    size_t         n_str, used_str;
    znp_status     st;
    size_t         err_pos;
} znp_parser;

static int perr(znp_parser *p, znp_status st, size_t pos)
{
    if (p->st == ZNP_OK) {
        p->st = st;
        p->err_pos = pos;
    }
    return 0;
}

static void skip_ws(znp_parser *p)
{
    while (p->pos < p->n) {
        uint8_t c = p->h[p->pos];
        if (c != ' ' && c != '\t' && c != '\n' && c != '\r')
            break;
        p->pos++;
    }
}

static uint32_t new_node(znp_parser *p, int type, size_t pos)
{
    if (p->used_nodes >= p->n_nodes) {
        perr(p, ZNP_ERR_SCRATCH, pos);
        return NIL;
    }
    znp_node *x = &p->nodes[p->used_nodes];
    memset(x, 0, sizeof *x);
    x->type = (uint8_t)type;
    x->pos = (uint32_t)pos;
    x->child = NIL;
    x->next = NIL;
    return (uint32_t)p->used_nodes++;
}

static int put_utf8(znp_parser *p, uint32_t cp, size_t pos)
{
    char buf[4];
    size_t k;
    if (cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
        return perr(p, ZNP_ERR_ENCODING, pos);
    if (cp < 0x80) {
        buf[0] = (char)cp; k = 1;
    } else if (cp < 0x800) {
        buf[0] = (char)(0xC0 | (cp >> 6));
        buf[1] = (char)(0x80 | (cp & 0x3F)); k = 2;
    } else if (cp < 0x10000) {
        buf[0] = (char)(0xE0 | (cp >> 12));
        buf[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        buf[2] = (char)(0x80 | (cp & 0x3F)); k = 3;
    } else {
        buf[0] = (char)(0xF0 | (cp >> 18));
        buf[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        buf[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
        buf[3] = (char)(0x80 | (cp & 0x3F)); k = 4;
    }
    if (p->used_str + k + 1 > p->n_str)
        return perr(p, ZNP_ERR_SCRATCH, pos);
    memcpy(p->str + p->used_str, buf, k);
    p->used_str += k;
    return 1;
}

static int hexval(uint8_t c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* A quoted string, decoded to UTF-8 in the string buffer. Escapes: \\ \'
   \" \n \t \r \xHH \uHHHH \UHHHHHHHH. NUL is refused, escaped or not:
   R's strings cannot hold it. */
static uint32_t parse_string(znp_parser *p)
{
    size_t start = p->pos;
    uint8_t q = p->h[p->pos++];
    uint32_t id = new_node(p, N_STR, start);
    if (id == NIL)
        return NIL;
    p->nodes[id].str = (uint32_t)p->used_str;
    for (;;) {
        if (p->pos >= p->n) {
            perr(p, ZNP_ERR_SYNTAX, p->pos);
            return NIL;
        }
        size_t at = p->pos;
        uint8_t c = p->h[p->pos++];
        if (c == q)
            break;
        if (c == '\n' || c == '\r') {
            perr(p, ZNP_ERR_SYNTAX, at);
            return NIL;
        }
        if (c != '\\') {
            if (c < 0x80 || !p->utf8) {
                /* Latin-1: a byte is its code point. */
                if (!put_utf8(p, c, at))
                    return NIL;
            } else {
                /* UTF-8, already validated whole: copy the sequence. */
                if (p->used_str + 2 > p->n_str) {
                    perr(p, ZNP_ERR_SCRATCH, at);
                    return NIL;
                }
                p->str[p->used_str++] = (char)c;
            }
            continue;
        }
        if (p->pos >= p->n) {
            perr(p, ZNP_ERR_SYNTAX, p->pos);
            return NIL;
        }
        uint8_t e = p->h[p->pos++];
        int digits = 0;
        uint32_t cp = 0;
        switch (e) {
        case '\\': cp = '\\'; break;
        case '\'': cp = '\''; break;
        case '"':  cp = '"';  break;
        case 'n':  cp = '\n'; break;
        case 't':  cp = '\t'; break;
        case 'r':  cp = '\r'; break;
        case 'x':  digits = 2; break;
        case 'u':  digits = 4; break;
        case 'U':  digits = 8; break;
        default:
            perr(p, ZNP_ERR_SYNTAX, at);
            return NIL;
        }
        for (int k = 0; k < digits; k++) {
            int v = p->pos < p->n ? hexval(p->h[p->pos]) : -1;
            if (v < 0) {
                perr(p, ZNP_ERR_SYNTAX, p->pos);
                return NIL;
            }
            cp = (cp << 4) | (uint32_t)v;
            p->pos++;
        }
        if (!put_utf8(p, cp, at))
            return NIL;
    }
    p->nodes[id].len = (uint32_t)(p->used_str - p->nodes[id].str);
    if (p->used_str + 1 > p->n_str) {
        perr(p, ZNP_ERR_SCRATCH, start);
        return NIL;
    }
    p->str[p->used_str++] = '\0';
    return id;
}

/* An integer as Python writes one: an optional minus, then 0 or a digit
   string without a leading zero. */
static uint32_t parse_int(znp_parser *p)
{
    size_t start = p->pos;
    if (p->h[p->pos] == '-')
        p->pos++;
    size_t d0 = p->pos;
    while (p->pos < p->n && p->h[p->pos] >= '0' && p->h[p->pos] <= '9')
        p->pos++;
    size_t nd = p->pos - d0;
    if (nd == 0 || (nd > 1 && p->h[d0] == '0')) {
        perr(p, ZNP_ERR_SYNTAX, start);
        return NIL;
    }
    uint32_t id = new_node(p, N_INT, start);
    if (id == NIL)
        return NIL;
    int64_t v = 0;
    const char *first = (const char *)p->h + start;
    const char *last = (const char *)p->h + p->pos;
    zuf_result r = zuf_parse_i64(first, last, &v);
    if (r.status == ZUF_ERR_RANGE)
        p->nodes[id].type = N_BIGINT;
    else if (r.status != ZUF_OK || r.ptr != last) {
        perr(p, ZNP_ERR_SYNTAX, start);
        return NIL;
    }
    p->nodes[id].i = v;
    return id;
}

static int match_word(znp_parser *p, const char *w)
{
    size_t k = strlen(w);
    if (p->n - p->pos < k || memcmp(p->h + p->pos, w, k) != 0)
        return 0;
    /* Not the prefix of a longer identifier, such as Trueish. */
    if (p->pos + k < p->n) {
        uint8_t c = p->h[p->pos + k];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '_' || c >= 0x80)
            return 0;
    }
    p->pos += k;
    return 1;
}

static uint32_t parse_value(znp_parser *p, int depth);

/* The items of a tuple, list or dict, up to the closing bracket. A dict
   reads key ':' value pairs. Returns the number of items (pairs for a
   dict), and sets *had_comma when a comma followed the last one. */
static int parse_items(znp_parser *p, uint32_t parent, uint8_t close,
                       int is_dict, int depth, int *had_comma)
{
    uint32_t last = NIL;
    int count = 0;
    *had_comma = 0;
    for (;;) {
        skip_ws(p);
        if (p->pos >= p->n)
            return perr(p, ZNP_ERR_SYNTAX, p->pos), -1;
        if (p->h[p->pos] == close) {
            p->pos++;
            return count;
        }
        if (count > 0 && !*had_comma)
            return perr(p, ZNP_ERR_SYNTAX, p->pos), -1;
        for (int part = 0; part < (is_dict ? 2 : 1); part++) {
            if (part == 1) {
                skip_ws(p);
                if (p->pos >= p->n || p->h[p->pos] != ':')
                    return perr(p, ZNP_ERR_SYNTAX, p->pos), -1;
                p->pos++;
            }
            uint32_t v = parse_value(p, depth);
            if (v == NIL)
                return -1;
            if (last == NIL)
                p->nodes[parent].child = v;
            else
                p->nodes[last].next = v;
            last = v;
            p->nodes[parent].n++;
        }
        count++;
        skip_ws(p);
        *had_comma = 0;
        if (p->pos < p->n && p->h[p->pos] == ',') {
            p->pos++;
            *had_comma = 1;
        }
    }
}

static uint32_t parse_value(znp_parser *p, int depth)
{
    skip_ws(p);
    if (p->pos >= p->n) {
        perr(p, ZNP_ERR_SYNTAX, p->pos);
        return NIL;
    }
    size_t start = p->pos;
    uint8_t c = p->h[p->pos];

    if (c == '{' || c == '[' || c == '(') {
        if (depth >= ZNP_MAX_DEPTH) { /* GUARD: depth */
            perr(p, ZNP_ERR_DEPTH, start);
            return NIL;
        }
        p->pos++;
        int type = c == '{' ? N_DICT : c == '[' ? N_LIST : N_TUPLE;
        uint8_t close = c == '{' ? '}' : c == '[' ? ']' : ')';
        uint32_t id = new_node(p, type, start);
        if (id == NIL)
            return NIL;
        int had_comma;
        int k = parse_items(p, id, close, type == N_DICT, depth + 1, &had_comma);
        if (k < 0)
            return NIL;
        /* (x) is x in parentheses, not a tuple: Python needs (x,). */
        if (type == N_TUPLE && k == 1 && !had_comma)
            return p->nodes[id].child;
        return id;
    }
    if (c == '\'' || c == '"')
        return parse_string(p);
    if (c == '-' || (c >= '0' && c <= '9'))
        return parse_int(p);
    if (match_word(p, "True") || match_word(p, "False")) {
        uint32_t id = new_node(p, N_BOOL, start);
        if (id != NIL)
            p->nodes[id].i = p->h[start] == 'T';
        return id;
    }
    if (match_word(p, "None"))
        return new_node(p, N_NONE, start);
    perr(p, ZNP_ERR_SYNTAX, start);
    return NIL;
}

/* ---- step 3: the meaning ------------------------------------------------ */

typedef struct {
    znp_parser       *p;
    const znp_limits *lim;
    znp_plan         *plan;
    znp_field        *fields;
    size_t            cap_fields;
    znp_span         *spans;
    uint64_t          columns;  /* R columns so far: fields, subarrays expanded */
} znp_ctx;

static const char *node_str(const znp_parser *p, uint32_t id)
{
    return p->str + p->nodes[id].str;
}

static int str_is(const znp_parser *p, uint32_t id, const char *s)
{
    const znp_node *x = &p->nodes[id];
    return x->type == N_STR && x->len == strlen(s) &&
           memcmp(p->str + x->str, s, x->len) == 0;
}

static int is_unit(const char *u, size_t n)
{
    static const char *units[] = {"Y", "M", "W", "D", "h", "m", "s",
                                  "ms", "us", "ns", "ps", "fs", "as"};
    for (size_t i = 0; i < sizeof units / sizeof units[0]; i++)
        if (strlen(units[i]) == n && memcmp(units[i], u, n) == 0)
            return 1;
    return 0;
}

/* A descr string (design 9.3) into a dtype. pos is the string's offset in
   the header, for faults. */
static int parse_descr(znp_ctx *c, uint32_t id, znp_dtype *dt)
{
    znp_parser *p = c->p;
    const char *s = node_str(p, id);
    size_t n = p->nodes[id].len, i = 0;
    size_t pos = p->nodes[id].pos;
    char order = 0;

    memset(dt, 0, sizeof *dt);
    if (i < n && (s[i] == '<' || s[i] == '>' || s[i] == '|' || s[i] == '='))
        order = s[i++];
    if (i >= n)
        return perr(p, ZNP_ERR_DESCR, pos);
    char kind = s[i++];
    if (kind == 'a')
        kind = 'S';

    uint64_t width = 0;
    size_t w0 = i;
    while (i < n && s[i] >= '0' && s[i] <= '9') {
        uint64_t d = (uint64_t)(s[i] - '0');
        if (width > (UINT64_MAX - d) / 10)
            return perr(p, ZNP_ERR_DESCR, pos);
        width = width * 10 + d;
        i++;
    }
    int has_width = i > w0;

    if (kind == 'O' || kind == 'g' || kind == 'G')
        return perr(p, ZNP_ERR_UNSUPPORTED, pos);
    if (!has_width)
        return perr(p, ZNP_ERR_DESCR, pos);
    /* Long double: no R type holds it. */
    if ((kind == 'f' && (width == 12 || width == 16)) ||
        (kind == 'c' && (width == 24 || width == 32)))
        return perr(p, ZNP_ERR_UNSUPPORTED, pos);

    int ok;
    switch (kind) {
    case 'b': ok = width == 1; break;
    case 'i': case 'u': ok = width == 1 || width == 2 || width == 4 || width == 8; break;
    case 'f': ok = width == 2 || width == 4 || width == 8; break;
    case 'c': ok = width == 8 || width == 16; break;
    case 'S': case 'U': case 'V': ok = 1; break;
    case 'M': case 'm': ok = width == 8; break;
    default: ok = 0;
    }
    if (!ok)
        return perr(p, ZNP_ERR_DESCR, pos);

    if (kind == 'M' || kind == 'm') {
        if (i >= n || s[i] != '[')
            return perr(p, ZNP_ERR_DESCR, pos);
        size_t u0 = ++i;
        while (i < n && s[i] != ']')
            i++;
        if (i >= n || !is_unit(s + u0, i - u0))
            return perr(p, ZNP_ERR_DESCR, pos);
        memcpy(dt->unit, s + u0, i - u0);
        i++;
    }
    if (i != n)
        return perr(p, ZNP_ERR_DESCR, pos);

    if (kind == 'U') {
        if (width > UINT64_MAX / 4)
            return perr(p, ZNP_ERR_DESCR, pos);
        dt->chars = width;
        dt->itemsize = width * 4;
    } else {
        dt->chars = kind == 'S' ? width : 0;
        dt->itemsize = width;
    }
    dt->kind = kind;

    /* One-byte kinds take '|'; multi-byte kinds take '<' or '>'. NumPy
       writes nothing else, and a mismatch is the first thing a fuzzer
       finds. '=' and no order are read as little-endian and reported. */
    int one_byte = kind == 'b' || kind == 'S' || kind == 'V' ||
                   ((kind == 'i' || kind == 'u') && width == 1);
    if (one_byte) {
        if (order == '<' || order == '>')
            return perr(p, ZNP_ERR_DESCR, pos);
        dt->order = '|';
    } else {
        if (order == '|')
            return perr(p, ZNP_ERR_DESCR, pos);
        if (order == '=' || order == 0) {
            c->plan->native_order = 1;
            order = '<';
        }
        dt->order = order;
    }
    return 1;
}

/* A shape: a tuple of non-negative ints (or a single int, for a subarray
   field). Writes at most cap dimensions; more is dims_status. */
static int parse_shape(znp_ctx *c, uint32_t id, uint64_t *shape, int cap,
                       int allow_int, znp_status dims_status, int *ndim)
{
    znp_parser *p = c->p;
    znp_node *x = &p->nodes[id];
    if (allow_int && (x->type == N_INT || x->type == N_BIGINT)) {
        if (x->type == N_BIGINT || x->i < 0)
            return perr(p, ZNP_ERR_SHAPE, x->pos);
        shape[0] = (uint64_t)x->i;
        *ndim = 1;
        return 1;
    }
    if (x->type != N_TUPLE)
        return perr(p, ZNP_ERR_TYPE, x->pos);
    if ((int64_t)x->n > (int64_t)cap) /* GUARD: dims */
        return perr(p, dims_status, x->pos);
    int k = 0;
    for (uint32_t d = x->child; d != NIL; d = p->nodes[d].next) {
        znp_node *e = &p->nodes[d];
        if (e->type != N_INT && e->type != N_BIGINT)
            return perr(p, ZNP_ERR_TYPE, e->pos);
        if (e->type == N_BIGINT || e->i < 0) /* GUARD: negative-dim */
            return perr(p, ZNP_ERR_SHAPE, e->pos);
        shape[k++] = (uint64_t)e->i;
    }
    *ndim = k;
    return 1;
}

static int add_field(znp_ctx *c, size_t pos, znp_field **out)
{
    znp_parser *p = c->p;
    if (c->plan->n_fields >= c->lim->max_fields) /* GUARD: fields */
        return perr(p, ZNP_ERR_FIELDS_LIMIT, pos);
    if ((size_t)c->plan->n_fields >= c->cap_fields)
        return perr(p, ZNP_ERR_SCRATCH, pos);
    *out = &c->fields[c->plan->n_fields++];
    memset(*out, 0, sizeof **out);
    return 1;
}

/* A field's type: a descr string; a nested list is refused (design 2). */
static int field_type(znp_ctx *c, uint32_t id, znp_dtype *dt)
{
    znp_parser *p = c->p;
    znp_node *x = &p->nodes[id];
    if (x->type == N_LIST || x->type == N_DICT)
        return perr(p, ZNP_ERR_UNSUPPORTED, x->pos);
    if (x->type != N_STR)
        return perr(p, ZNP_ERR_TYPE, x->pos);
    return parse_descr(c, id, dt);
}

/* NumPy names a field declared with an empty name f<index>. */
static int generated_name(znp_ctx *c, znp_field *f, int index, size_t pos)
{
    znp_parser *p = c->p;
    char buf[24];
    size_t k = 0;
    char digits[12];
    int nd = 0;
    unsigned v = (unsigned)index;
    do {
        digits[nd++] = (char)('0' + v % 10);
        v /= 10;
    } while (v > 0);
    buf[k++] = 'f';
    while (nd > 0)
        buf[k++] = digits[--nd];
    if (p->used_str + k + 1 > p->n_str)
        return perr(p, ZNP_ERR_SCRATCH, pos);
    memcpy(p->str + p->used_str, buf, k);
    p->str[p->used_str + k] = '\0';
    f->name = p->str + p->used_str;
    f->name_len = k;
    p->used_str += k + 1;
    return 1;
}

/* A field's size, and the columns it makes in R: one, or one per element
   of a subarray. The columns of all fields together are bounded by
   max_fields, so that no header can ask the build phase for more columns
   than that, whatever the element width (a subarray of zero-width elements
   has no bytes to compare with the input). */
static int finish_field(znp_ctx *c, znp_field *f, size_t pos)
{
    uint64_t n = 1;
    for (int d = 0; d < f->ndim; d++)
        n = sat_mul(n, f->shape[d]);
    f->size = sat_mul(f->dtype.itemsize, n);
    c->columns = sat_add(c->columns, n);
    if (c->columns > (uint64_t)c->lim->max_fields) /* GUARD: columns */
        return perr(c->p, ZNP_ERR_FIELDS_LIMIT, pos);
    return 1;
}

static int same_name(const znp_field *a, const znp_field *b)
{
    return a->name_len == b->name_len && memcmp(a->name, b->name, a->name_len) == 0;
}

/* Quadratic, but n is at most max_fields (1,024 by default). */
static int names_unique(znp_ctx *c, size_t pos)
{
    for (int i = 0; i < c->plan->n_fields; i++)
        for (int j = 0; j < i; j++)
            if (same_name(&c->fields[i], &c->fields[j])) /* GUARD: duplicate-field */
                return perr(c->p, ZNP_ERR_LAYOUT, pos);
    return 1;
}

/* The list form: [(name, descr), (name, descr, shape), ...], where name may
   be (title, name). ('', '|V<n>') is padding, as NumPy writes it for
   aligned and offset dtypes. */
static int parse_record_list(znp_ctx *c, uint32_t id)
{
    znp_parser *p = c->p;
    uint64_t offset = 0;
    int index = 0;
    for (uint32_t e = p->nodes[id].child; e != NIL; e = p->nodes[e].next, index++) {
        znp_node *t = &p->nodes[e];
        if (t->type != N_TUPLE || t->n < 2 || t->n > 3)
            return perr(p, ZNP_ERR_TYPE, t->pos);
        uint32_t nm = t->child;
        uint32_t ty = p->nodes[nm].next;
        uint32_t sh = p->nodes[ty].next;

        uint32_t title = NIL;
        if (p->nodes[nm].type == N_TUPLE && p->nodes[nm].n == 2) {
            title = p->nodes[nm].child;
            nm = p->nodes[title].next;
            if (p->nodes[title].type != N_STR)
                return perr(p, ZNP_ERR_TYPE, p->nodes[title].pos);
        }
        if (p->nodes[nm].type != N_STR)
            return perr(p, ZNP_ERR_TYPE, p->nodes[nm].pos);

        znp_dtype dt;
        if (!field_type(c, ty, &dt))
            return 0;
        uint64_t sub[ZNP_MAX_SUBDIMS];
        int sub_ndim = 0;
        if (sh != NIL &&
            !parse_shape(c, sh, sub, ZNP_MAX_SUBDIMS, 1, ZNP_ERR_UNSUPPORTED, &sub_ndim))
            return 0;

        if (p->nodes[nm].len == 0 && dt.kind == 'V' && sub_ndim == 0 && title == NIL) {
            offset = sat_add(offset, dt.itemsize);
            continue;
        }
        znp_field *f;
        if (!add_field(c, t->pos, &f))
            return 0;
        f->dtype = dt;
        f->ndim = sub_ndim;
        memcpy(f->shape, sub, sizeof sub);
        if (p->nodes[nm].len == 0) {
            if (!generated_name(c, f, index, t->pos))
                return 0;
        } else {
            f->name = node_str(p, nm);
            f->name_len = p->nodes[nm].len;
        }
        if (title != NIL) {
            f->title = node_str(p, title);
            f->title_len = p->nodes[title].len;
        }
        f->offset = offset;
        if (!finish_field(c, f, t->pos))
            return 0;
        offset = sat_add(offset, f->size);
    }
    c->plan->itemsize = offset;
    return names_unique(c, p->nodes[id].pos);
}

static int span_cmp(const void *a, const void *b)
{
    const znp_span *x = a, *y = b;
    return (x->off > y->off) - (x->off < y->off);
}

/* The dict form: {'names': [...], 'formats': [...], 'offsets': [...],
   'itemsize': n, 'titles': [...], 'aligned': bool}. names and formats are
   required. Fields may not overlap or run past the itemsize. */
static int parse_record_dict(znp_ctx *c, uint32_t id)
{
    znp_parser *p = c->p;
    uint32_t names = NIL, formats = NIL, offsets = NIL, itemsize = NIL, titles = NIL;
    for (uint32_t k = p->nodes[id].child; k != NIL; k = p->nodes[p->nodes[k].next].next) {
        uint32_t v = p->nodes[k].next;
        uint32_t *slot = NULL;
        if (str_is(p, k, "names")) slot = &names;
        else if (str_is(p, k, "formats")) slot = &formats;
        else if (str_is(p, k, "offsets")) slot = &offsets;
        else if (str_is(p, k, "itemsize")) slot = &itemsize;
        else if (str_is(p, k, "titles")) slot = &titles;
        else if (str_is(p, k, "aligned")) {
            if (p->nodes[v].type != N_BOOL)
                return perr(p, ZNP_ERR_TYPE, p->nodes[v].pos);
            continue;
        } else
            return perr(p, ZNP_ERR_KEY, p->nodes[k].pos);
        if (*slot != NIL)
            return perr(p, ZNP_ERR_KEY, p->nodes[k].pos);
        *slot = v;
    }
    if (names == NIL || formats == NIL)
        return perr(p, ZNP_ERR_KEY, p->nodes[id].pos);
    uint32_t n = p->nodes[names].n;
    if (p->nodes[names].type != N_LIST || p->nodes[formats].type != N_LIST)
        return perr(p, ZNP_ERR_TYPE, p->nodes[names].pos);
    if (p->nodes[formats].n != n)
        return perr(p, ZNP_ERR_LAYOUT, p->nodes[formats].pos);
    if (offsets != NIL && (p->nodes[offsets].type != N_LIST || p->nodes[offsets].n != n))
        return perr(p, ZNP_ERR_LAYOUT, p->nodes[offsets].pos);
    if (titles != NIL && (p->nodes[titles].type != N_LIST || p->nodes[titles].n != n))
        return perr(p, ZNP_ERR_LAYOUT, p->nodes[titles].pos);

    uint32_t nm = p->nodes[names].child, fm = p->nodes[formats].child;
    uint32_t of = offsets == NIL ? NIL : p->nodes[offsets].child;
    uint32_t tt = titles == NIL ? NIL : p->nodes[titles].child;
    uint64_t next_offset = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (p->nodes[nm].type != N_STR)
            return perr(p, ZNP_ERR_TYPE, p->nodes[nm].pos);
        znp_field *f;
        if (!add_field(c, p->nodes[nm].pos, &f))
            return 0;
        if (!field_type(c, fm, &f->dtype))
            return 0;
        if (p->nodes[nm].len == 0) {
            if (!generated_name(c, f, (int)i, p->nodes[nm].pos))
                return 0;
        } else {
            f->name = node_str(p, nm);
            f->name_len = p->nodes[nm].len;
        }
        if (of != NIL) {
            znp_node *o = &p->nodes[of];
            if (o->type != N_INT && o->type != N_BIGINT)
                return perr(p, ZNP_ERR_TYPE, o->pos);
            if (o->type == N_BIGINT || o->i < 0)
                return perr(p, ZNP_ERR_LAYOUT, o->pos);
            f->offset = (uint64_t)o->i;
            of = o->next;
        } else
            f->offset = next_offset;
        if (tt != NIL) {
            znp_node *t = &p->nodes[tt];
            if (t->type == N_STR) {
                f->title = node_str(p, tt);
                f->title_len = t->len;
            } else if (t->type != N_NONE)
                return perr(p, ZNP_ERR_TYPE, t->pos);
            tt = t->next;
        }
        if (!finish_field(c, f, p->nodes[nm].pos))
            return 0;
        next_offset = sat_add(f->offset, f->size);
        nm = p->nodes[nm].next;
        fm = p->nodes[fm].next;
    }

    /* The record size: declared, or the end of the furthest field. */
    uint64_t end = 0;
    for (int i = 0; i < c->plan->n_fields; i++) {
        uint64_t e = sat_add(c->fields[i].offset, c->fields[i].size);
        if (e > end)
            end = e;
    }
    if (itemsize != NIL) {
        znp_node *x = &p->nodes[itemsize];
        if (x->type != N_INT && x->type != N_BIGINT)
            return perr(p, ZNP_ERR_TYPE, x->pos);
        if (x->type == N_BIGINT || x->i < 0)
            return perr(p, ZNP_ERR_LAYOUT, x->pos);
        if ((uint64_t)x->i < end) /* GUARD: field-past-itemsize */
            return perr(p, ZNP_ERR_LAYOUT, x->pos);
        c->plan->itemsize = (uint64_t)x->i;
    } else
        c->plan->itemsize = end;

    /* No two fields share a byte. */
    for (int i = 0; i < c->plan->n_fields; i++) {
        c->spans[i].off = c->fields[i].offset;
        c->spans[i].size = c->fields[i].size;
    }
    qsort(c->spans, (size_t)c->plan->n_fields, sizeof *c->spans, span_cmp);
    for (int i = 1; i < c->plan->n_fields; i++)
        if (sat_add(c->spans[i - 1].off, c->spans[i - 1].size) > c->spans[i].off) /* GUARD: overlap */
            return perr(p, ZNP_ERR_LAYOUT, p->nodes[offsets == NIL ? id : offsets].pos);
    return names_unique(c, p->nodes[id].pos);
}

static int interpret(znp_ctx *c, uint32_t root)
{
    znp_parser *p = c->p;
    znp_plan *plan = c->plan;
    if (p->nodes[root].type != N_DICT)
        return perr(p, ZNP_ERR_TYPE, p->nodes[root].pos);

    uint32_t descr = NIL, order = NIL, shape = NIL;
    for (uint32_t k = p->nodes[root].child; k != NIL; k = p->nodes[p->nodes[k].next].next) {
        uint32_t v = p->nodes[k].next;
        uint32_t *slot;
        if (p->nodes[k].type != N_STR) /* GUARD: key-type */
            return perr(p, ZNP_ERR_TYPE, p->nodes[k].pos);
        if (str_is(p, k, "descr")) slot = &descr;
        else if (str_is(p, k, "fortran_order")) slot = &order;
        else if (str_is(p, k, "shape")) slot = &shape;
        else
            return perr(p, ZNP_ERR_KEY, p->nodes[k].pos);
        if (*slot != NIL) /* GUARD: duplicate-key */
            return perr(p, ZNP_ERR_KEY, p->nodes[k].pos);
        *slot = v;
    }
    if (descr == NIL || order == NIL || shape == NIL)
        return perr(p, ZNP_ERR_KEY, p->nodes[root].pos);

    if (p->nodes[order].type != N_BOOL)
        return perr(p, ZNP_ERR_TYPE, p->nodes[order].pos);
    plan->fortran_order = (int)p->nodes[order].i;

    if (!parse_shape(c, shape, plan->shape, c->lim->max_dims, 0,
                     ZNP_ERR_DIMS_LIMIT, &plan->ndim))
        return 0;

    switch (p->nodes[descr].type) {
    case N_STR:
        if (!parse_descr(c, descr, &plan->dtype))
            return 0;
        plan->itemsize = plan->dtype.itemsize;
        return 1;
    case N_LIST:
        plan->structured = 1;
        return parse_record_list(c, descr);
    case N_DICT:
        plan->structured = 1;
        return parse_record_dict(c, descr);
    default:
        return perr(p, ZNP_ERR_TYPE, p->nodes[descr].pos);
    }
}

znp_status znp_check(const uint8_t *data, size_t size,
                     const znp_limits *lim, void *scratch, size_t scratch_size,
                     znp_plan *plan, znp_fault *fault)
{
    size_t need;
    znp_status st = znp_check_prefix(data, size, lim, plan, &need, fault);
    if (st != ZNP_OK)
        return st;
    if (lim->max_dims < 0 || lim->max_dims > ZNP_MAX_DIMS_CAP || lim->max_fields < 0 ||
        scratch == NULL || scratch_size < need)
        return fail(fault, ZNP_ERR_SCRATCH, 0);

    znp_layout L;
    scratch_layout(plan->header_len, lim, &L);
    char *base = scratch;

    const uint8_t *h = data + plan->header_offset;
    size_t hn = (size_t)plan->header_len;
    if (plan->major == 3 && !zuf_utf8_valid((const char *)h, hn))
        return fail(fault, ZNP_ERR_ENCODING, plan->header_offset);

    znp_parser p;
    memset(&p, 0, sizeof p);
    p.h = h;
    p.n = hn;
    p.utf8 = plan->major == 3;
    p.nodes = (znp_node *)(void *)base;
    p.n_nodes = L.n_nodes;
    p.str = base + L.off_str;
    p.n_str = L.n_str;
    p.st = ZNP_OK;

    /* The dict is the whole header: '{' first, then only whitespace after
       the closing brace (spaces and the newline NumPy pads with). */
    uint32_t root = NIL;
    if (hn == 0 || h[0] != '{')
        perr(&p, hn == 0 ? ZNP_ERR_TRUNCATED : ZNP_ERR_SYNTAX, 0);
    else {
        root = parse_value(&p, 0);
        if (root != NIL) {
            skip_ws(&p);
            if (p.pos != hn)
                perr(&p, ZNP_ERR_SYNTAX, p.pos);
        }
    }

    znp_ctx c;
    c.p = &p;
    c.lim = lim;
    c.plan = plan;
    c.fields = (znp_field *)(void *)(base + L.off_fields);
    c.cap_fields = L.n_fields;
    c.spans = (znp_span *)(void *)(base + L.off_sort);
    c.columns = 0;
    plan->fields = c.fields;

    if (p.st == ZNP_OK)
        interpret(&c, root);
    if (p.st != ZNP_OK)
        return fail(fault, p.st, plan->header_offset + p.err_pos);

    /* The declared size against the limit and the bytes present (design
       12). Saturating, so a shape of (2**40, 2**40) costs nothing. */
    plan->count = 1;
    for (int d = 0; d < plan->ndim; d++)
        plan->count = sat_mul(plan->count, plan->shape[d]);
    plan->data_bytes = sat_mul(plan->count, plan->itemsize);
    uint64_t avail = (uint64_t)size - plan->data_offset;

    /* No element is larger than the whole input may be: with no elements
       (a zero dimension) nothing else would bound it, and the build phase
       sizes buffers by it (a U<n> value is decoded in 4n bytes). */
    if (plan->itemsize > lim->max_size) /* GUARD: itemsize */
        return fail(fault, ZNP_ERR_SIZE_LIMIT, plan->header_offset);
    /* A zero-width type (S0, V0, an empty record) declares elements with no
       bytes behind them; the build phase would still allocate one R value
       each, so their number is bounded by max_size too. */
    if (plan->itemsize == 0 && plan->count > lim->max_size) /* GUARD: zero-width */
        return fail(fault, ZNP_ERR_SIZE_LIMIT, plan->header_offset);
    if (plan->data_bytes > lim->max_size) /* GUARD: declared-size */
        return fail(fault, ZNP_ERR_SIZE_LIMIT, plan->header_offset);
    if (lim->header_only)
        return ZNP_OK;
    if (plan->data_bytes > avail) /* GUARD: data-truncated */
        return fail(fault, ZNP_ERR_TRUNCATED, size);
    if (plan->data_bytes < avail) /* GUARD: trailing */
        return fail(fault, ZNP_ERR_TRAILING, plan->data_offset + plan->data_bytes);
    return ZNP_OK;
}
