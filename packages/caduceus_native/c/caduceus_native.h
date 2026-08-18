#ifndef CADUCEUS_NATIVE_H
#define CADUCEUS_NATIVE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef _WIN32
#define CADUCEUS_EXPORT __declspec(dllexport)
#else
#define CADUCEUS_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Phase 1: Markdown & Streaming Text Processing                             */
/* ========================================================================= */

typedef struct {
    int32_t start_offset;
    int32_t end_offset;
    int32_t is_fence;
} CaduceusBlockSpan;

/**
 * Scans markdown text and identifies settled block spans.
 * Returns the number of settled blocks found, and writes spans into out_spans.
 * max_spans: capacity of out_spans buffer.
 * out_tail_start: offset where the un-settled tail begins.
 */
CADUCEUS_EXPORT int32_t caduceus_markdown_split_blocks(
    const char *text,
    int32_t text_len,
    CaduceusBlockSpan *out_spans,
    int32_t max_spans,
    int32_t *out_tail_start
);

/**
 * Normalizes text for memory fingerprinting:
 * - Converts to lowercase
 * - Strips leading markdown list markers, headings, emphasis characters
 * - Collapses consecutive whitespace to a single space
 * - Strips trailing punctuation
 * Writes result to out_buf (null-terminated). Returns written length (excluding null).
 */
CADUCEUS_EXPORT int32_t caduceus_normalize_fingerprint(
    const char *input,
    int32_t input_len,
    char *out_buf,
    int32_t out_capacity
);


/* ========================================================================= */
/* Phase 2: High Throughput Cryptography & JSON Frame Extraction              */
/* ========================================================================= */

/**
 * Computes SHA-256 hash of input data.
 * out_hash must be at least 32 bytes.
 */
CADUCEUS_EXPORT void caduceus_sha256(
    const uint8_t *data,
    size_t len,
    uint8_t out_hash[32]
);

/**
 * Generates an Ed25519 public key and secret key from a 32-byte seed.
 * seed: 32 bytes
 * out_public_key: 32 bytes
 * out_secret_key: 64 bytes (seed || public_key)
 */
CADUCEUS_EXPORT void caduceus_ed25519_keypair_from_seed(
    const uint8_t seed[32],
    uint8_t out_public_key[32],
    uint8_t out_secret_key[64]
);

/**
 * Signs a message using Ed25519 secret key.
 * message: message buffer
 * message_len: length of message
 * secret_key: 64-byte secret key (or 32-byte seed + 32-byte pubkey)
 * out_signature: 64 bytes
 */
CADUCEUS_EXPORT void caduceus_ed25519_sign(
    const uint8_t *message,
    size_t message_len,
    const uint8_t secret_key[64],
    uint8_t out_signature[64]
);

/**
 * Verifies an Ed25519 signature.
 * Returns 1 if valid, 0 if invalid.
 */
CADUCEUS_EXPORT int32_t caduceus_ed25519_verify(
    const uint8_t *message,
    size_t message_len,
    const uint8_t public_key[32],
    const uint8_t signature[64]
);

/**
 * Fast JSON field extractor for JSON-RPC / OpenClaw gateway frames.
 * Extracts the value of `fieldName` as a raw string slice without full AST parsing.
 * Returns 1 if found (with start and end offsets), 0 if not found.
 */
CADUCEUS_EXPORT int32_t caduceus_json_extract_string_field(
    const char *json_str,
    int32_t json_len,
    const char *field_name,
    int32_t *out_val_start,
    int32_t *out_val_end
);

/**
 * Fast zero-copy JSON field extractor directly from raw UTF-8 byte arrays.
 * Extracts the value of `fieldName` without needing prior Dart String allocation.
 */
CADUCEUS_EXPORT int32_t caduceus_json_extract_from_bytes(
    const uint8_t *bytes,
    int32_t len,
    const char *field_name,
    int32_t *out_val_start,
    int32_t *out_val_end
);


/* ========================================================================= */
/* Phase 3 & Extensions: SIMD Math, Batch Vector Top-K & Diffing             */
/* ========================================================================= */

typedef struct {
    int32_t index;
    float score;
} CaduceusVectorMatch;

/**
 * Calculates Cosine Similarity between two float vectors.
 * Uses SIMD optimizations (ARM NEON / AVX) where available.
 */
CADUCEUS_EXPORT float caduceus_cosine_similarity(
    const float *a,
    const float *b,
    int32_t dim
);

/**
 * Computes cosine similarities between one query vector and N candidate vectors (stored in contiguous matrix).
 * out_scores must have capacity for at least count floats.
 */
CADUCEUS_EXPORT void caduceus_batch_cosine_similarity(
    const float *query,
    const float *matrix,
    int32_t dim,
    int32_t count,
    float *out_scores
);

/**
 * Fast SIMD-accelerated Top-K vector similarity search.
 * Finds the top K most similar vectors to query in matrix.
 * Returns the actual count of matches written into out_matches (min(k, count)).
 */
CADUCEUS_EXPORT int32_t caduceus_top_k_similar_vectors(
    const float *query,
    const float *matrix,
    int32_t dim,
    int32_t count,
    int32_t k,
    CaduceusVectorMatch *out_matches
);

/**
 * Calculates Dot Product between two float vectors.
 */
CADUCEUS_EXPORT float caduceus_dot_product(
    const float *a,
    const float *b,
    int32_t dim
);

/**
 * Calculates Euclidean (L2) distance between two float vectors.
 */
CADUCEUS_EXPORT float caduceus_euclidean_distance(
    const float *a,
    const float *b,
    int32_t dim
);

/**
 * Calculates Levenshtein edit distance between two strings.
 */
CADUCEUS_EXPORT int32_t caduceus_levenshtein_distance(
    const char *s1,
    int32_t len1,
    const char *s2,
    int32_t len2
);

/**
 * Calculates normalized string similarity ratio in [0.0, 1.0].
 * 1.0 = identical, 0.0 = completely different.
 */
CADUCEUS_EXPORT float caduceus_string_similarity(
    const char *s1,
    int32_t len1,
    const char *s2,
    int32_t len2
);

#ifdef __cplusplus
}
#endif

#endif /* CADUCEUS_NATIVE_H */
