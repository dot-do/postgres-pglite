#!/bin/bash
#
# build-pglite-vector.sh - Vector-optimized PGLite build with pgvector
#
# =============================================================================
# OVERVIEW
# =============================================================================
#
# This creates a vector-optimized PGLite build for AI/ML workloads:
# - pgvector extension pre-bundled (HNSW and IVFFlat indexes)
# - JSON/JSONB for metadata storage
# - English-only Snowball stemmer (for RAG/search use cases)
# - UTF-8 only charset converters
# - Optimized for vector similarity search
#
# =============================================================================
# TARGET SIZE AND MEMORY
# =============================================================================
#
# Target: ~9.5MB total bundle, ~60-65MB runtime memory
#
# Size breakdown:
#   - WASM binary: ~8.5MB (core PostgreSQL)
#   - Data bundle: ~4.7MB (LZ4 compressed - share/lib/password)
#   - Vector ext:  ~45KB (pgvector extension tarball)
#   - JS runtime:  ~100KB (Emscripten module loader)
#   - Total:       ~9.5MB (compressed transfer)
#
# Memory footprint:
#   - Initial:     32MB (Emscripten heap)
#   - After init:  ~60-65MB
#   - Growth:      ALLOW_MEMORY_GROWTH enabled, stays within 128MB
#
# =============================================================================
# USE CASES
# =============================================================================
#
# Ideal for:
# - RAG (Retrieval-Augmented Generation) applications
# - Semantic search with embeddings
# - AI agent memory storage
# - Vector similarity search
# - Recommendation systems
# - Hybrid search (combining FTS + vector)
#
# NOT ideal for:
# - Simple CRUD without vector operations (use pglite-minimal)
# - Multi-language text processing (use pglite-full)
# - Cryptographic operations (use pglite-full)
#
# =============================================================================
# USAGE
# =============================================================================
#
#   ./build-pglite-vector.sh              # Standard vector build
#   DEBUG=true ./build-pglite-vector.sh   # Debug build with symbols
#
# =============================================================================
# ENVIRONMENT VARIABLES
# =============================================================================
#
#   DEBUG=true/false      - Build debug or release version (default: false)
#   TOTAL_MEMORY          - Override initial memory allocation (default: 64MB)
#   CMA_MB                - Wire query zone size in MB (default: 8)
#   PREBUNDLE_VECTOR      - Pre-bundle vector extension (default: true)
#
# =============================================================================

set -e

# Ensure we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "
================================================================================
                    PGLite VECTOR Build - AI/ML Optimized
================================================================================

Building vector-optimized PGLite with pgvector extension:
  - pgvector 0.8.0 extension (HNSW + IVFFlat indexes)
  - All vector distance functions (L2, cosine, inner product)
  - JSON/JSONB for metadata storage
  - English full-text search for hybrid search
  - UTF-8 only charset support (~1.8MB savings)
  - English-only stemmer (~500KB savings)
  - Optimized for size (-Oz with LTO)

Target bundle size: ~9.5MB

"

# =============================================================================
# VECTOR BUILD CONFIGURATION
# =============================================================================

# Force release mode for size optimization (unless explicitly debugging)
export DEBUG=${DEBUG:-false}

# Variant identification
export PGLITE_VARIANT="vector"
export PGLITE_VARIANT_DESC="AI/ML optimized with pgvector"

# UTF-8 only - excludes all non-UTF-8 charset converters
# This saves ~1.8MB since we don't need Latin, CJK, or other converters
# UTF-8 is the standard for modern AI/ML applications
export PGLITE_UTF8_ONLY=true

# English-only Snowball stemmer
# This saves ~500KB by excluding 27+ language stemmers
# Provides English FTS for hybrid search (FTS + vector)
export SNOWBALL_LANGUAGES=english

# Memory configuration optimized for Cloudflare Workers 128MB limit
# Vector operations need slightly more memory than minimal
export TOTAL_MEMORY=${TOTAL_MEMORY:-64MB}

# CMA (Contiguous Memory Area) for wire protocol
# 8MB is sufficient for most queries including large embedding arrays
export CMA_MB=${CMA_MB:-8}

# Pre-bundle vector extension in the data file
export PREBUNDLE_VECTOR=${PREBUNDLE_VECTOR:-true}

# Size optimization compiler flags
# -Oz: Optimize for smallest binary size (over speed)
# -flto: Link-time optimization for dead code elimination
# -fno-exceptions: No C++ exceptions (PostgreSQL is C)
export COPTS="-Oz -flto -fno-exceptions"
export LOPTS="-Oz -flto -fno-exceptions --closure=0 -sASSERTIONS=0"

# Output directories
export PGLITE_VECTOR_DIST=${PGLITE_VECTOR_DIST:-/tmp/pglite-vector}

# =============================================================================
# DISPLAY CONFIGURATION
# =============================================================================

echo "
Configuration:
  PGLITE_VARIANT:     $PGLITE_VARIANT
  DEBUG:              $DEBUG
  PGLITE_UTF8_ONLY:   $PGLITE_UTF8_ONLY
  SNOWBALL_LANGUAGES: $SNOWBALL_LANGUAGES
  PREBUNDLE_VECTOR:   $PREBUNDLE_VECTOR
  TOTAL_MEMORY:       $TOTAL_MEMORY
  CMA_MB:             $CMA_MB
  Output Directory:   $PGLITE_VECTOR_DIST

Compiler Flags:
  COPTS: $COPTS
  LOPTS: $LOPTS

===============================================================================
INCLUDED FEATURES (Vector Optimized)
===============================================================================

pgvector Extension (v0.8.0):
  + vector type with configurable dimensions (up to 16,000)
  + halfvec type (half-precision, 50% memory savings)
  + sparsevec type (sparse vectors for high-dimensional data)
  + HNSW index (fast approximate nearest neighbor)
  + IVFFlat index (inverted file with flat compression)
  + L2 distance operator (<->)
  + Cosine distance operator (<=>)
  + Inner product operator (<#>)
  + Exact nearest neighbor search
  + Approximate nearest neighbor search with ef_search tuning

Core SQL Features:
  + SELECT, INSERT, UPDATE, DELETE
  + JOINs (INNER, LEFT, RIGHT, FULL, CROSS)
  + Subqueries and CTEs (WITH clause)
  + Window functions (ROW_NUMBER, RANK, etc.)
  + Aggregate functions (COUNT, SUM, AVG, etc.)
  + Prepared statements and parameterized queries

JSON/JSONB Support:
  + All JSON operators (->>, ->, @>, <@, ?, ?|, ?&)
  + GIN indexes for JSONB
  + JSON path queries
  + Ideal for storing metadata alongside embeddings

Full-Text Search (English):
  + to_tsvector('english', text)
  + to_tsquery('english', query)
  + ts_rank for relevance scoring
  + GIN indexes for tsvector
  + Perfect for hybrid search (FTS + vector similarity)

Data Types:
  + All standard PostgreSQL types
  + Arrays (int[], text[], float[], etc.)
  + UUID for unique identifiers
  + Timestamp with timezone

===============================================================================
EXCLUDED FEATURES (for smaller size)
===============================================================================

  - Non-English Snowball stemmers (26 languages)
  - Non-UTF-8 charset converters (Latin, CJK, etc.)
  - pgcrypto (encryption functions)
  - ltree, hstore, intarray extensions
  - ICU collation

===============================================================================
TYPICAL USE CASES
===============================================================================

RAG Application:
  CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1536),
    metadata JSONB
  );
  CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
  SELECT content FROM documents
  ORDER BY embedding <=> \$query_embedding
  LIMIT 5;

Semantic Search:
  SELECT content,
         1 - (embedding <=> \$query) as similarity
  FROM articles
  WHERE embedding <=> \$query < 0.5
  ORDER BY embedding <=> \$query
  LIMIT 10;

AI Agent Memory:
  CREATE TABLE agent_memory (
    id SERIAL PRIMARY KEY,
    role TEXT,
    content TEXT,
    embedding vector(384),
    timestamp TIMESTAMPTZ DEFAULT NOW()
  );

"

# =============================================================================
# BUILD PROCESS
# =============================================================================

echo "
================================================================================
Starting Vector variant build...
================================================================================
"

# Step 1: Run the main WASM build with vector optimizations
echo "Step 1: Running base WASM build with optimizations..."
if [ -f "wasm-build.sh" ]; then
    ./wasm-build.sh
else
    echo "ERROR: wasm-build.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Step 2: Build the vector extension if not already built
echo ""
echo "Step 2: Ensuring pgvector extension is built..."

# Check if vector extension exists in different locations
VECTOR_BUILT=false

if [ -f "${PGROOT:-/tmp/pglite}/lib/postgresql/vector.so" ]; then
    echo "pgvector extension already installed in PGROOT"
    VECTOR_BUILT=true
fi

if [ -f "pglite/vector/vector.so" ]; then
    echo "pgvector extension found in pglite/vector/"
    VECTOR_BUILT=true
fi

if ! $VECTOR_BUILT; then
    echo "Building pgvector extension..."
    if [ -f "extra/vector.sh" ]; then
        ./extra/vector.sh
    else
        echo "WARNING: extra/vector.sh not found, vector extension may not be available"
    fi
fi

# Step 3: Create variant-specific output directory and copy files
echo ""
echo "Step 3: Creating vector variant distribution..."
mkdir -p "$PGLITE_VECTOR_DIST"

# Copy the core WASM files
WEB_DIST="${PGL_DIST_WEB:-/tmp/sdk/dist/pglite-web}"
if [ -d "$WEB_DIST" ]; then
    cp -v "$WEB_DIST"/pglite.* "$PGLITE_VECTOR_DIST/" 2>/dev/null || true
fi

# Copy vector extension tarball if available
EXT_DIST="${PG_DIST_EXT:-/tmp/sdk/dist/extensions-emsdk}"
if [ -f "$EXT_DIST/vector.tar.gz" ]; then
    cp -v "$EXT_DIST/vector.tar.gz" "$PGLITE_VECTOR_DIST/"
elif [ -f "$EXT_DIST/vector.tar" ]; then
    cp -v "$EXT_DIST/vector.tar" "$PGLITE_VECTOR_DIST/"
fi

# =============================================================================
# POST-BUILD SIZE REPORT
# =============================================================================

echo "
================================================================================
                    PGLite VECTOR Build - Size Report
================================================================================
"

TOTAL_BYTES=0

if [ -f "$PGLITE_VECTOR_DIST/pglite.wasm" ]; then
    WASM_BYTES=$(stat -f%z "$PGLITE_VECTOR_DIST/pglite.wasm" 2>/dev/null || stat -c%s "$PGLITE_VECTOR_DIST/pglite.wasm" 2>/dev/null)
    WASM_MB=$(echo "scale=2; $WASM_BYTES / 1048576" | bc)
    echo "WASM bundle size: ${WASM_MB}MB ($WASM_BYTES bytes)"
    TOTAL_BYTES=$((TOTAL_BYTES + WASM_BYTES))
fi

if [ -f "$PGLITE_VECTOR_DIST/pglite.data" ]; then
    DATA_BYTES=$(stat -f%z "$PGLITE_VECTOR_DIST/pglite.data" 2>/dev/null || stat -c%s "$PGLITE_VECTOR_DIST/pglite.data" 2>/dev/null)
    DATA_MB=$(echo "scale=2; $DATA_BYTES / 1048576" | bc)
    echo "Data bundle size: ${DATA_MB}MB ($DATA_BYTES bytes)"
    TOTAL_BYTES=$((TOTAL_BYTES + DATA_BYTES))
fi

if [ -f "$PGLITE_VECTOR_DIST/vector.tar.gz" ]; then
    VEC_BYTES=$(stat -f%z "$PGLITE_VECTOR_DIST/vector.tar.gz" 2>/dev/null || stat -c%s "$PGLITE_VECTOR_DIST/vector.tar.gz" 2>/dev/null)
    VEC_KB=$(echo "scale=2; $VEC_BYTES / 1024" | bc)
    echo "Vector extension: ${VEC_KB}KB ($VEC_BYTES bytes)"
    TOTAL_BYTES=$((TOTAL_BYTES + VEC_BYTES))
fi

if [ -f "$PGLITE_VECTOR_DIST/pglite.js" ]; then
    JS_BYTES=$(stat -f%z "$PGLITE_VECTOR_DIST/pglite.js" 2>/dev/null || stat -c%s "$PGLITE_VECTOR_DIST/pglite.js" 2>/dev/null)
    JS_KB=$(echo "scale=2; $JS_BYTES / 1024" | bc)
    echo "JS wrapper size:  ${JS_KB}KB ($JS_BYTES bytes)"
    TOTAL_BYTES=$((TOTAL_BYTES + JS_BYTES))
fi

if [ "$TOTAL_BYTES" -gt 0 ]; then
    TOTAL_MB=$(echo "scale=2; $TOTAL_BYTES / 1048576" | bc)
    echo ""
    echo "Total bundle:     ${TOTAL_MB}MB ($TOTAL_BYTES bytes)"

    # Check against 9.5MB target
    TARGET_BYTES=9961472  # 9.5MB
    if [ "$TOTAL_BYTES" -le "$TARGET_BYTES" ]; then
        echo "  [OK] Within 9.5MB target"
    else
        OVER_MB=$(echo "scale=2; ($TOTAL_BYTES - $TARGET_BYTES) / 1048576" | bc)
        echo "  [WARNING] Exceeds 9.5MB target by ${OVER_MB}MB"
    fi
fi

echo "
================================================================================

Vector build complete! Output files in: $PGLITE_VECTOR_DIST

Files produced:
  - pglite.wasm     - WebAssembly binary (core PostgreSQL)
  - pglite.data     - Filesystem bundle (share/lib/password)
  - pglite.js       - JavaScript module loader
  - vector.tar.gz   - pgvector extension bundle

Usage with Cloudflare Workers:

  import { PGlite } from '@dotdo/pglite'
  import { vector } from '@dotdo/pglite/vector'
  import pgliteWasm from './pglite.wasm'
  import pgliteData from './pglite.data'

  const pg = await PGlite.create({
    wasmModule: pgliteWasm,
    fsBundle: new Blob([pgliteData]),
    extensions: { vector }
  })

  await pg.exec('CREATE EXTENSION IF NOT EXISTS vector')
  await pg.exec(\`
    CREATE TABLE embeddings (
      id SERIAL PRIMARY KEY,
      content TEXT,
      embedding vector(1536)
    )
  \`)

Memory Budget (128MB Cloudflare Workers):
  - Static bundle:  ~9.5MB (WASM + data + JS + vector)
  - After init:     ~60-65MB
  - Available:      ~60-65MB for queries, embeddings, and results

Comparison with other variants:
  - pglite-tiny:    ~3MB   - Absolute minimum, basic types only
  - pglite-minimal: ~5MB   - Core SQL, all types, no extensions
  - pglite-json:    ~4MB   - JSON/JSONB optimized
  - pglite-fts:     ~6MB   - Full-text search with English stemmer
  - pglite-vector:  ~9.5MB - AI/ML with pgvector (THIS BUILD)
  - pglite-full:    ~13MB  - All features and extensions

================================================================================
"
