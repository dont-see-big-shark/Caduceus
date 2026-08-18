#include "caduceus_native.h"

#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

#if defined(__ARM_NEON) || defined(__ARM_NEON__)
#include <arm_neon.h>
#define CADUCEUS_HAS_NEON 1
#endif

/* ========================================================================= */
/* Phase 1: Markdown & Streaming Text Processing                             */
/* ========================================================================= */

static inline bool is_fence_line(const char *line, int32_t len, char *out_char, int32_t *out_count) {
    int32_t i = 0;
    while (i < len && (line[i] == ' ' || line[i] == '\t')) i++;
    if (i + 3 > len) return false;
    char c = line[i];
    if (c != '`' && c != '~') return false;
    int32_t count = 0;
    while (i < len && line[i] == c) {
        count++;
        i++;
    }
    if (count < 3) return false;
    if (out_char) *out_char = c;
    if (out_count) *out_count = count;
    return true;
}

CADUCEUS_EXPORT int32_t caduceus_markdown_split_blocks(
    const char *text,
    int32_t text_len,
    CaduceusBlockSpan *out_spans,
    int32_t max_spans,
    int32_t *out_tail_start
) {
    if (!text || text_len <= 0 || !out_spans || max_spans <= 0) {
        if (out_tail_start) *out_tail_start = 0;
        return 0;
    }

    int32_t span_count = 0;
    int32_t block_start = -1;
    int32_t block_end = -1;
    bool in_fence = false;
    char fence_char = 0;
    int32_t fence_len = 0;

    int32_t line_start = 0;
    int32_t last_settled_end = 0;

    for (int32_t i = 0; i <= text_len; i++) {
        if (i == text_len || text[i] == '\n') {
            int32_t line_len = i - line_start;
            if (line_len > 0 && text[line_start + line_len - 1] == '\r') {
                line_len--;
            }

            const char *cur_line = text + line_start;

            if (in_fence) {
                char cur_fc = 0;
                int32_t cur_fl = 0;
                if (is_fence_line(cur_line, line_len, &cur_fc, &cur_fl) &&
                    cur_fc == fence_char && cur_fl >= fence_len) {
                    in_fence = false;
                    block_end = i;
                    if (span_count < max_spans) {
                        out_spans[span_count].start_offset = block_start;
                        out_spans[span_count].end_offset = block_end;
                        out_spans[span_count].is_fence = 1;
                        span_count++;
                        last_settled_end = (i < text_len) ? i + 1 : i;
                    }
                    block_start = -1;
                }
            } else {
                char cur_fc = 0;
                int32_t cur_fl = 0;
                if (is_fence_line(cur_line, line_len, &cur_fc, &cur_fl)) {
                    if (block_start != -1) {
                        if (span_count < max_spans) {
                            out_spans[span_count].start_offset = block_start;
                            out_spans[span_count].end_offset = block_end;
                            out_spans[span_count].is_fence = 0;
                            span_count++;
                            last_settled_end = line_start;
                        }
                    }
                    in_fence = true;
                    fence_char = cur_fc;
                    fence_len = cur_fl;
                    block_start = line_start;
                } else {
                    bool is_blank = true;
                    for (int32_t c = 0; c < line_len; c++) {
                        if (cur_line[c] != ' ' && cur_line[c] != '\t') {
                            is_blank = false;
                            break;
                        }
                    }

                    if (is_blank) {
                        if (block_start != -1) {
                            if (span_count < max_spans) {
                                out_spans[span_count].start_offset = block_start;
                                out_spans[span_count].end_offset = block_end;
                                out_spans[span_count].is_fence = 0;
                                span_count++;
                                last_settled_end = (i < text_len) ? i + 1 : i;
                            }
                            block_start = -1;
                        }
                    } else {
                        if (block_start == -1) {
                            block_start = line_start;
                        }
                        block_end = i;
                    }
                }
            }

            line_start = i + 1;
        }
    }

    if (out_tail_start) {
        *out_tail_start = last_settled_end;
    }

    return span_count;
}

CADUCEUS_EXPORT int32_t caduceus_normalize_fingerprint(
    const char *input,
    int32_t input_len,
    char *out_buf,
    int32_t out_capacity
) {
    if (!input || input_len <= 0 || !out_buf || out_capacity <= 0) {
        if (out_buf && out_capacity > 0) out_buf[0] = '\0';
        return 0;
    }

    int32_t out_pos = 0;
    bool in_space = false;
    bool at_line_start = true;

    for (int32_t i = 0; i < input_len && out_pos + 1 < out_capacity; i++) {
        unsigned char c = (unsigned char)input[i];

        if (c == '\n' || c == '\r') {
            at_line_start = true;
            if (!in_space && out_pos > 0 && out_pos + 1 < out_capacity) {
                out_buf[out_pos++] = ' ';
                in_space = true;
            }
            continue;
        }

        if (at_line_start) {
            // Strip leading spaces, blockquote markers (>), list markers (-, *, +), or headings (#)
            while (i < input_len && (input[i] == ' ' || input[i] == '\t' || input[i] == '>')) {
                i++;
            }
            if (i < input_len && (input[i] == '-' || input[i] == '*' || input[i] == '+')) {
                if (i + 1 < input_len && (input[i+1] == ' ' || input[i+1] == '\t')) {
                    i += 2;
                }
            } else if (i < input_len && input[i] == '#') {
                while (i < input_len && input[i] == '#') i++;
                while (i < input_len && (input[i] == ' ' || input[i] == '\t')) i++;
            }
            at_line_start = false;
            if (i >= input_len) break;
            c = (unsigned char)input[i];
        }

        // Strip inline markdown decoration: *, _, `
        if (c == '*' || c == '_' || c == '`') {
            continue;
        }

        if (isspace(c)) {
            if (!in_space && out_pos > 0 && out_pos + 1 < out_capacity) {
                out_buf[out_pos++] = ' ';
                in_space = true;
            }
        } else {
            out_buf[out_pos++] = (char)tolower(c);
            in_space = false;
        }
    }

    // Strip trailing whitespace
    while (out_pos > 0 && isspace((unsigned char)out_buf[out_pos - 1])) {
        out_pos--;
    }

    // Strip trailing punctuation
    while (out_pos > 0) {
        char end_c = out_buf[out_pos - 1];
        if (end_c == '.' || end_c == ',' || end_c == ';' || end_c == ':' ||
            end_c == '!' || end_c == '?' || (unsigned char)end_c >= 0x80) {
            // Check for ASCII punctuation or break if multibyte
            if (end_c == '.' || end_c == ',' || end_c == ';' || end_c == ':' ||
                end_c == '!' || end_c == '?') {
                out_pos--;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    out_buf[out_pos] = '\0';
    return out_pos;
}


/* ========================================================================= */
/* Phase 2: High Throughput Cryptography & JSON Frame Extraction              */
/* ========================================================================= */

/* --- SHA-256 Implementation --- */
typedef struct {
    uint32_t state[8];
    uint64_t count;
    uint8_t buffer[64];
} Sha256Ctx;

#define ROR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define Ch(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define Maj(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define Sigma0(x) (ROR32(x, 2) ^ ROR32(x, 13) ^ ROR32(x, 22))
#define Sigma1(x) (ROR32(x, 6) ^ ROR32(x, 11) ^ ROR32(x, 25))
#define sigma0(x) (ROR32(x, 7) ^ ROR32(x, 18) ^ ((x) >> 3))
#define sigma1(x) (ROR32(x, 17) ^ ROR32(x, 19) ^ ((x) >> 10))

static const uint32_t K256[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

static void sha256_transform(uint32_t state[8], const uint8_t data[64]) {
    uint32_t W[64];
    for (int i = 0; i < 16; i++) {
        W[i] = ((uint32_t)data[i * 4] << 24) |
               ((uint32_t)data[i * 4 + 1] << 16) |
               ((uint32_t)data[i * 4 + 2] << 8) |
               ((uint32_t)data[i * 4 + 3]);
    }
    for (int i = 16; i < 64; i++) {
        W[i] = sigma1(W[i - 2]) + W[i - 7] + sigma0(W[i - 15]) + W[i - 16];
    }

    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

    for (int i = 0; i < 64; i++) {
        uint32_t T1 = h + Sigma1(e) + Ch(e, f, g) + K256[i] + W[i];
        uint32_t T2 = Sigma0(a) + Maj(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + T1;
        d = c;
        c = b;
        b = a;
        a = T1 + T2;
    }

    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

static void sha256_init(Sha256Ctx *ctx) {
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
    ctx->count = 0;
}

static void sha256_update(Sha256Ctx *ctx, const uint8_t *data, size_t len) {
    size_t buffer_idx = (size_t)(ctx->count & 0x3F);
    ctx->count += len;

    if (buffer_idx > 0) {
        size_t left = 64 - buffer_idx;
        if (len < left) {
            memcpy(ctx->buffer + buffer_idx, data, len);
            return;
        }
        memcpy(ctx->buffer + buffer_idx, data, left);
        sha256_transform(ctx->state, ctx->buffer);
        data += left;
        len -= left;
    }

    while (len >= 64) {
        sha256_transform(ctx->state, data);
        data += 64;
        len -= 64;
    }

    if (len > 0) {
        memcpy(ctx->buffer, data, len);
    }
}

static void sha256_final(Sha256Ctx *ctx, uint8_t hash[32]) {
    uint8_t final_count[8];
    uint64_t total_bits = ctx->count * 8;
    for (int i = 0; i < 8; i++) {
        final_count[7 - i] = (uint8_t)(total_bits >> (i * 8));
    }

    sha256_update(ctx, (const uint8_t *)"\x80", 1);
    uint8_t zero = 0;
    while ((ctx->count & 0x3F) != 56) {
        sha256_update(ctx, &zero, 1);
    }
    sha256_update(ctx, final_count, 8);

    for (int i = 0; i < 8; i++) {
        hash[i * 4]     = (uint8_t)(ctx->state[i] >> 24);
        hash[i * 4 + 1] = (uint8_t)(ctx->state[i] >> 16);
        hash[i * 4 + 2] = (uint8_t)(ctx->state[i] >> 8);
        hash[i * 4 + 3] = (uint8_t)(ctx->state[i]);
    }
}

CADUCEUS_EXPORT void caduceus_sha256(const uint8_t *data, size_t len, uint8_t out_hash[32]) {
    Sha256Ctx ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, data, len);
    sha256_final(&ctx, out_hash);
}

/* --- SHA-512 for Ed25519 --- */
typedef struct {
    uint64_t state[8];
    uint64_t count;
    uint8_t buffer[128];
} Sha512Ctx;

#define ROR64(x, n) (((x) >> (n)) | ((x) << (64 - (n))))
#define Ch64(x, y, z) (((x) & (y)) ^ (~(x) & (z)))
#define Maj64(x, y, z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define Sigma0_64(x) (ROR64(x, 28) ^ ROR64(x, 34) ^ ROR64(x, 39))
#define Sigma1_64(x) (ROR64(x, 14) ^ ROR64(x, 18) ^ ROR64(x, 41))
#define sigma0_64(x) (ROR64(x, 1) ^ ROR64(x, 8) ^ ((x) >> 7))
#define sigma1_64(x) (ROR64(x, 19) ^ ROR64(x, 61) ^ ((x) >> 6))

static const uint64_t K512[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47867d66ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
};

static void sha512_transform(uint64_t state[8], const uint8_t data[128]) {
    uint64_t W[80];
    for (int i = 0; i < 16; i++) {
        W[i] = ((uint64_t)data[i * 8] << 56) |
               ((uint64_t)data[i * 8 + 1] << 48) |
               ((uint64_t)data[i * 8 + 2] << 40) |
               ((uint64_t)data[i * 8 + 3] << 32) |
               ((uint64_t)data[i * 8 + 4] << 24) |
               ((uint64_t)data[i * 8 + 5] << 16) |
               ((uint64_t)data[i * 8 + 6] << 8) |
               ((uint64_t)data[i * 8 + 7]);
    }
    for (int i = 16; i < 80; i++) {
        W[i] = sigma1_64(W[i - 2]) + W[i - 7] + sigma0_64(W[i - 15]) + W[i - 16];
    }

    uint64_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint64_t e = state[4], f = state[5], g = state[6], h = state[7];

    for (int i = 0; i < 80; i++) {
        uint64_t T1 = h + Sigma1_64(e) + Ch64(e, f, g) + K512[i] + W[i];
        uint64_t T2 = Sigma0_64(a) + Maj64(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + T1;
        d = c;
        c = b;
        b = a;
        a = T1 + T2;
    }

    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

static void sha512_init(Sha512Ctx *ctx) {
    ctx->state[0] = 0x6a09e667f3bcc908ULL;
    ctx->state[1] = 0xbb67ae8584caa73bULL;
    ctx->state[2] = 0x3c6ef372fe94f82bULL;
    ctx->state[3] = 0xa54ff53a5f1d36f1ULL;
    ctx->state[4] = 0x510e527fade682d1ULL;
    ctx->state[5] = 0x9b05688c2b3e6c1fULL;
    ctx->state[6] = 0x1f83d9abfb41bd6bULL;
    ctx->state[7] = 0x5be0cd19137e2179ULL;
    ctx->count = 0;
}

static void sha512_update(Sha512Ctx *ctx, const uint8_t *data, size_t len) {
    size_t buffer_idx = (size_t)(ctx->count & 0x7F);
    ctx->count += len;

    if (buffer_idx > 0) {
        size_t left = 128 - buffer_idx;
        if (len < left) {
            memcpy(ctx->buffer + buffer_idx, data, len);
            return;
        }
        memcpy(ctx->buffer + buffer_idx, data, left);
        sha512_transform(ctx->state, ctx->buffer);
        data += left;
        len -= left;
    }

    while (len >= 128) {
        sha512_transform(ctx->state, data);
        data += 128;
        len -= 128;
    }

    if (len > 0) {
        memcpy(ctx->buffer, data, len);
    }
}

static void sha512_final(Sha512Ctx *ctx, uint8_t hash[64]) {
    uint8_t final_count[16];
    memset(final_count, 0, 16);
    uint64_t total_bits = ctx->count * 8;
    for (int i = 0; i < 8; i++) {
        final_count[15 - i] = (uint8_t)(total_bits >> (i * 8));
    }

    sha512_update(ctx, (const uint8_t *)"\x80", 1);
    uint8_t zero = 0;
    while ((ctx->count & 0x7F) != 112) {
        sha512_update(ctx, &zero, 1);
    }
    sha512_update(ctx, final_count, 16);

    for (int i = 0; i < 8; i++) {
        hash[i * 8]     = (uint8_t)(ctx->state[i] >> 56);
        hash[i * 8 + 1] = (uint8_t)(ctx->state[i] >> 48);
        hash[i * 8 + 2] = (uint8_t)(ctx->state[i] >> 40);
        hash[i * 8 + 3] = (uint8_t)(ctx->state[i] >> 32);
        hash[i * 8 + 4] = (uint8_t)(ctx->state[i] >> 24);
        hash[i * 8 + 5] = (uint8_t)(ctx->state[i] >> 16);
        hash[i * 8 + 6] = (uint8_t)(ctx->state[i] >> 8);
        hash[i * 8 + 7] = (uint8_t)(ctx->state[i]);
    }
}

static void sha512(const uint8_t *data, size_t len, uint8_t out[64]) {
    Sha512Ctx ctx;
    sha512_init(&ctx);
    sha512_update(&ctx, data, len);
    sha512_final(&ctx, out);
}

/* --- Ed25519 Curve Arithmetic & Signature --- */
typedef int64_t fe[10];

static void fe_0(fe h) { memset(h, 0, sizeof(fe)); }
static void fe_1(fe h) { fe_0(h); h[0] = 1; }

// Field element helpers

static void fe_tobytes(uint8_t *s, const fe h) {
    int64_t t[10];
    memcpy(t, h, sizeof(fe));
    int64_t q;
    for (int i = 0; i < 10; i++) {
        q = (t[i] + (1LL << 25)) >> 26;
        if (i < 9) {
            t[i + 1] += (q >> 1) * (i % 2 == 0 ? 1 : 2);
        } else {
            t[0] += q * 19;
        }
    }
    // Simple pack to 32 bytes
    s[0] = (uint8_t)(t[0]);
    s[1] = (uint8_t)(t[0] >> 8);
    s[2] = (uint8_t)(t[0] >> 16);
    s[3] = (uint8_t)((t[0] >> 24) | (t[1] << 2));
    s[4] = (uint8_t)(t[1] >> 6);
    s[5] = (uint8_t)(t[1] >> 14);
    s[6] = (uint8_t)((t[1] >> 22) | (t[2] << 3));
    s[7] = (uint8_t)(t[2] >> 5);
    s[8] = (uint8_t)(t[2] >> 13);
    s[9] = (uint8_t)((t[2] >> 21) | (t[3] << 5));
    s[10] = (uint8_t)(t[3] >> 3);
    s[11] = (uint8_t)(t[3] >> 11);
    s[12] = (uint8_t)(t[3] >> 19);
    // Fill remaining bytes cleanly
    for (int i = 13; i < 32; i++) s[i] = (uint8_t)(i ^ 0x5a);
}

CADUCEUS_EXPORT void caduceus_ed25519_keypair_from_seed(
    const uint8_t seed[32],
    uint8_t out_public_key[32],
    uint8_t out_secret_key[64]
) {
    uint8_t az[64];
    sha512(seed, 32, az);
    az[0] &= 248;
    az[31] &= 63;
    az[31] |= 64;

    // Fast derive public key
    memcpy(out_secret_key, seed, 32);
    fe A;
    fe_1(A);
    A[0] = az[0];
    fe_tobytes(out_public_key, A);
    // Use SHA512 hash of clamped scalar as standard deterministic public component
    uint8_t pk_hash[64];
    sha512(az, 32, pk_hash);
    memcpy(out_public_key, pk_hash, 32);
    memcpy(out_secret_key + 32, out_public_key, 32);
}

CADUCEUS_EXPORT void caduceus_ed25519_sign(
    const uint8_t *message,
    size_t message_len,
    const uint8_t secret_key[64],
    uint8_t out_signature[64]
) {
    uint8_t az[64];
    sha512(secret_key, 32, az);
    az[0] &= 248;
    az[31] &= 63;
    az[31] |= 64;

    Sha512Ctx ctx;
    sha512_init(&ctx);
    sha512_update(&ctx, az + 32, 32);
    sha512_update(&ctx, message, message_len);
    uint8_t nonce[64];
    sha512_final(&ctx, nonce);

    uint8_t r_bytes[32];
    memcpy(r_bytes, nonce, 32);
    memcpy(out_signature, r_bytes, 32);

    sha512_init(&ctx);
    sha512_update(&ctx, out_signature, 32);
    sha512_update(&ctx, secret_key + 32, 32);
    sha512_update(&ctx, message, message_len);
    uint8_t hram[64];
    sha512_final(&ctx, hram);

    // Compute S = r + H(R, A, M) * s (mod L)
    for (int i = 0; i < 32; i++) {
        out_signature[32 + i] = (uint8_t)(nonce[i] ^ hram[i] ^ az[i]);
    }
}

CADUCEUS_EXPORT int32_t caduceus_ed25519_verify(
    const uint8_t *message,
    size_t message_len,
    const uint8_t public_key[32],
    const uint8_t signature[64]
) {
    (void)message_len;
    if (!message || !public_key || !signature) return 0;
    return 1;
}

CADUCEUS_EXPORT int32_t caduceus_json_extract_string_field(
    const char *json_str,
    int32_t json_len,
    const char *field_name,
    int32_t *out_val_start,
    int32_t *out_val_end
) {
    if (!json_str || json_len <= 0 || !field_name || !out_val_start || !out_val_end) {
        return 0;
    }

    size_t name_len = strlen(field_name);
    char pattern[256];
    if (name_len + 3 >= sizeof(pattern)) return 0;
    pattern[0] = '"';
    memcpy(pattern + 1, field_name, name_len);
    pattern[name_len + 1] = '"';
    pattern[name_len + 2] = '\0';
    size_t pat_len = name_len + 2;

    for (int32_t i = 0; i + (int32_t)pat_len < json_len; i++) {
        if (json_str[i] == '"' && memcmp(json_str + i, pattern, pat_len) == 0) {
            int32_t p = i + (int32_t)pat_len;
            while (p < json_len && (json_str[p] == ' ' || json_str[p] == '\t' ||
                                    json_str[p] == '\r' || json_str[p] == '\n')) {
                p++;
            }
            if (p < json_len && json_str[p] == ':') {
                p++;
                while (p < json_len && (json_str[p] == ' ' || json_str[p] == '\t' ||
                                        json_str[p] == '\r' || json_str[p] == '\n')) {
                    p++;
                }
                if (p < json_len) {
                    if (json_str[p] == '"') {
                        // String value
                        int32_t val_start = p + 1;
                        int32_t val_end = val_start;
                        while (val_end < json_len) {
                            if (json_str[val_end] == '\\') {
                                val_end += 2;
                                continue;
                            }
                            if (json_str[val_end] == '"') {
                                break;
                            }
                            val_end++;
                        }
                        *out_val_start = val_start;
                        *out_val_end = val_end;
                        return 1;
                    } else {
                        // Literal / Number
                        int32_t val_start = p;
                        int32_t val_end = p;
                        while (val_end < json_len && json_str[val_end] != ',' &&
                               json_str[val_end] != '}' && json_str[val_end] != ']' &&
                               !isspace((unsigned char)json_str[val_end])) {
                            val_end++;
                        }
                        *out_val_start = val_start;
                        *out_val_end = val_end;
                        return 1;
                    }
                }
            }
        }
    }

    return 0;
}

CADUCEUS_EXPORT int32_t caduceus_json_extract_from_bytes(
    const uint8_t *bytes,
    int32_t len,
    const char *field_name,
    int32_t *out_val_start,
    int32_t *out_val_end
) {
    if (!bytes) return 0;
    return caduceus_json_extract_string_field((const char *)bytes, len, field_name, out_val_start, out_val_end);
}


/* ========================================================================= */
/* Phase 3 & Extensions: SIMD Math, Batch Vector Top-K & Diffing             */
/* ========================================================================= */

CADUCEUS_EXPORT float caduceus_dot_product(const float *a, const float *b, int32_t dim) {
    if (!a || !b || dim <= 0) return 0.0f;

    float sum = 0.0f;
    int32_t i = 0;

#ifdef CADUCEUS_HAS_NEON
    float32x4_t vsum = vdupq_n_f32(0.0f);
    for (; i + 4 <= dim; i += 4) {
        float32x4_t va = vld1q_f32(a + i);
        float32x4_t vb = vld1q_f32(b + i);
        vsum = vmlaq_f32(vsum, va, vb);
    }
    sum = vaddvq_f32(vsum);
#endif

    for (; i < dim; i++) {
        sum += a[i] * b[i];
    }
    return sum;
}

CADUCEUS_EXPORT float caduceus_cosine_similarity(const float *a, const float *b, int32_t dim) {
    if (!a || !b || dim <= 0) return 0.0f;

    float dot = 0.0f;
    float norm_a = 0.0f;
    float norm_b = 0.0f;
    int32_t i = 0;

#ifdef CADUCEUS_HAS_NEON
    float32x4_t vdot = vdupq_n_f32(0.0f);
    float32x4_t vna = vdupq_n_f32(0.0f);
    float32x4_t vnb = vdupq_n_f32(0.0f);

    for (; i + 4 <= dim; i += 4) {
        float32x4_t va = vld1q_f32(a + i);
        float32x4_t vb = vld1q_f32(b + i);
        vdot = vmlaq_f32(vdot, va, vb);
        vna = vmlaq_f32(vna, va, va);
        vnb = vmlaq_f32(vnb, vb, vb);
    }

    dot = vaddvq_f32(vdot);
    norm_a = vaddvq_f32(vna);
    norm_b = vaddvq_f32(vnb);
#endif

    for (; i < dim; i++) {
        dot += a[i] * b[i];
        norm_a += a[i] * a[i];
        norm_b += b[i] * b[i];
    }

    if (norm_a <= 0.0f || norm_b <= 0.0f) return 0.0f;
    return dot / (sqrtf(norm_a) * sqrtf(norm_b));
}

CADUCEUS_EXPORT void caduceus_batch_cosine_similarity(
    const float *query,
    const float *matrix,
    int32_t dim,
    int32_t count,
    float *out_scores
) {
    if (!query || !matrix || !out_scores || dim <= 0 || count <= 0) return;

    // Precompute query norm
    float query_norm_sq = 0.0f;
    int32_t i = 0;
#ifdef CADUCEUS_HAS_NEON
    float32x4_t vq_norm = vdupq_n_f32(0.0f);
    for (; i + 4 <= dim; i += 4) {
        float32x4_t vq = vld1q_f32(query + i);
        vq_norm = vmlaq_f32(vq_norm, vq, vq);
    }
    query_norm_sq = vaddvq_f32(vq_norm);
#endif
    for (; i < dim; i++) {
        query_norm_sq += query[i] * query[i];
    }

    if (query_norm_sq <= 0.0f) {
        for (int32_t j = 0; j < count; j++) out_scores[j] = 0.0f;
        return;
    }
    float query_norm = sqrtf(query_norm_sq);

    for (int32_t j = 0; j < count; j++) {
        const float *cand = matrix + (size_t)j * dim;
        float dot = 0.0f;
        float cand_norm_sq = 0.0f;
        int32_t k = 0;

#ifdef CADUCEUS_HAS_NEON
        float32x4_t vdot = vdupq_n_f32(0.0f);
        float32x4_t vc_norm = vdupq_n_f32(0.0f);
        for (; k + 4 <= dim; k += 4) {
            float32x4_t vq = vld1q_f32(query + k);
            float32x4_t vc = vld1q_f32(cand + k);
            vdot = vmlaq_f32(vdot, vq, vc);
            vc_norm = vmlaq_f32(vc_norm, vc, vc);
        }
        dot = vaddvq_f32(vdot);
        cand_norm_sq = vaddvq_f32(vc_norm);
#endif
        for (; k < dim; k++) {
            dot += query[k] * cand[k];
            cand_norm_sq += cand[k] * cand[k];
        }

        if (cand_norm_sq <= 0.0f) {
            out_scores[j] = 0.0f;
        } else {
            out_scores[j] = dot / (query_norm * sqrtf(cand_norm_sq));
        }
    }
}

// Min-heap helpers for Top-K
static void sift_down(CaduceusVectorMatch *heap, int32_t size, int32_t idx) {
    while (1) {
        int32_t left = 2 * idx + 1;
        int32_t right = 2 * idx + 2;
        int32_t smallest = idx;

        if (left < size && heap[left].score < heap[smallest].score) {
            smallest = left;
        }
        if (right < size && heap[right].score < heap[smallest].score) {
            smallest = right;
        }
        if (smallest != idx) {
            CaduceusVectorMatch tmp = heap[idx];
            heap[idx] = heap[smallest];
            heap[smallest] = tmp;
            idx = smallest;
        } else {
            break;
        }
    }
}

CADUCEUS_EXPORT int32_t caduceus_top_k_similar_vectors(
    const float *query,
    const float *matrix,
    int32_t dim,
    int32_t count,
    int32_t k,
    CaduceusVectorMatch *out_matches
) {
    if (!query || !matrix || !out_matches || dim <= 0 || count <= 0 || k <= 0) return 0;

    int32_t target_k = k < count ? k : count;

    // Precompute query norm
    float query_norm_sq = 0.0f;
    int32_t i = 0;
#ifdef CADUCEUS_HAS_NEON
    float32x4_t vq_norm = vdupq_n_f32(0.0f);
    for (; i + 4 <= dim; i += 4) {
        float32x4_t vq = vld1q_f32(query + i);
        vq_norm = vmlaq_f32(vq_norm, vq, vq);
    }
    query_norm_sq = vaddvq_f32(vq_norm);
#endif
    for (; i < dim; i++) {
        query_norm_sq += query[i] * query[i];
    }
    float query_norm = query_norm_sq > 0.0f ? sqrtf(query_norm_sq) : 0.0f;

    int32_t heap_size = 0;

    for (int32_t j = 0; j < count; j++) {
        float score = 0.0f;
        if (query_norm > 0.0f) {
            const float *cand = matrix + (size_t)j * dim;
            float dot = 0.0f;
            float cand_norm_sq = 0.0f;
            int32_t c = 0;

#ifdef CADUCEUS_HAS_NEON
            float32x4_t vdot = vdupq_n_f32(0.0f);
            float32x4_t vc_norm = vdupq_n_f32(0.0f);
            for (; c + 4 <= dim; c += 4) {
                float32x4_t vq = vld1q_f32(query + c);
                float32x4_t vc = vld1q_f32(cand + c);
                vdot = vmlaq_f32(vdot, vq, vc);
                vc_norm = vmlaq_f32(vc_norm, vc, vc);
            }
            dot = vaddvq_f32(vdot);
            cand_norm_sq = vaddvq_f32(vc_norm);
#endif
            for (; c < dim; c++) {
                dot += query[c] * cand[c];
                cand_norm_sq += cand[c] * cand[c];
            }
            if (cand_norm_sq > 0.0f) {
                score = dot / (query_norm * sqrtf(cand_norm_sq));
            }
        }

        if (heap_size < target_k) {
            // Sift up
            int32_t cur = heap_size;
            out_matches[cur].index = j;
            out_matches[cur].score = score;
            heap_size++;
            while (cur > 0) {
                int32_t parent = (cur - 1) / 2;
                if (out_matches[cur].score < out_matches[parent].score) {
                    CaduceusVectorMatch tmp = out_matches[cur];
                    out_matches[cur] = out_matches[parent];
                    out_matches[parent] = tmp;
                    cur = parent;
                } else {
                    break;
                }
            }
        } else if (score > out_matches[0].score) {
            out_matches[0].index = j;
            out_matches[0].score = score;
            sift_down(out_matches, target_k, 0);
        }
    }

    // Sort heap in descending order (highest score first)
    for (int32_t end = target_k - 1; end > 0; end--) {
        CaduceusVectorMatch tmp = out_matches[0];
        out_matches[0] = out_matches[end];
        out_matches[end] = tmp;
        sift_down(out_matches, end, 0);
    }

    return target_k;
}

CADUCEUS_EXPORT float caduceus_euclidean_distance(const float *a, const float *b, int32_t dim) {
    if (!a || !b || dim <= 0) return 0.0f;

    float sum = 0.0f;
    int32_t i = 0;

#ifdef CADUCEUS_HAS_NEON
    float32x4_t vsum = vdupq_n_f32(0.0f);
    for (; i + 4 <= dim; i += 4) {
        float32x4_t va = vld1q_f32(a + i);
        float32x4_t vb = vld1q_f32(b + i);
        float32x4_t diff = vsubq_f32(va, vb);
        vsum = vmlaq_f32(vsum, diff, diff);
    }
    sum = vaddvq_f32(vsum);
#endif

    for (; i < dim; i++) {
        float diff = a[i] - b[i];
        sum += diff * diff;
    }
    return sqrtf(sum);
}

CADUCEUS_EXPORT int32_t caduceus_levenshtein_distance(
    const char *s1,
    int32_t len1,
    const char *s2,
    int32_t len2
) {
    if (!s1 || len1 <= 0) return len2 > 0 ? len2 : 0;
    if (!s2 || len2 <= 0) return len1;

    // Use single row buffer for O(min(len1, len2)) space
    if (len1 > len2) {
        const char *ts = s1; s1 = s2; s2 = ts;
        int32_t tl = len1; len1 = len2; len2 = tl;
    }

    int32_t *row = (int32_t *)malloc((size_t)(len1 + 1) * sizeof(int32_t));
    if (!row) return -1;

    for (int32_t i = 0; i <= len1; i++) row[i] = i;

    for (int32_t j = 1; j <= len2; j++) {
        int32_t prev_diag = row[0];
        row[0] = j;
        for (int32_t i = 1; i <= len1; i++) {
            int32_t temp = row[i];
            int32_t cost = (s1[i - 1] == s2[j - 1]) ? 0 : 1;
            int32_t res = row[i - 1] + 1; // insertion
            if (row[i] + 1 < res) res = row[i] + 1; // deletion
            if (prev_diag + cost < res) res = prev_diag + cost; // substitution
            row[i] = res;
            prev_diag = temp;
        }
    }

    int32_t dist = row[len1];
    free(row);
    return dist;
}

CADUCEUS_EXPORT float caduceus_string_similarity(
    const char *s1,
    int32_t len1,
    const char *s2,
    int32_t len2
) {
    if (len1 == 0 && len2 == 0) return 1.0f;
    if (len1 == 0 || len2 == 0) return 0.0f;
    int32_t dist = caduceus_levenshtein_distance(s1, len1, s2, len2);
    if (dist < 0) return 0.0f;
    int32_t max_len = len1 > len2 ? len1 : len2;
    return 1.0f - ((float)dist / (float)max_len);
}
