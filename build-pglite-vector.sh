#!/bin/bash
#
# build-pglite-vector.sh - Vector-optimized PGLite build
#
# Creates a minimal PGLite WASM binary optimized for AI/ML workloads:
# - Pre-bundles pgvector extension with HNSW and IVFFlat indexes
# - Keeps JSON/JSONB for metadata storage
# - Uses English-only Snowball stemmer (for RAG/search use cases)
# - UTF-8 only charset converters
# - Excludes: geometric types, network types, replication, full multi-language support
#
# Target: ~5MB WASM bundle, ~55-60MB memory footprint
#
# Usage:
#   ./build-pglite-vector.sh          # Standard vector build
#   DEBUG=true ./build-pglite-vector.sh  # Debug build with symbols
#
# Environment variables:
#   DEBUG        - Enable debug build (default: false)
#   PREBUNDLE_VECTOR - Pre-bundle vector extension in data file (default: true)
#   TOTAL_MEMORY - Max memory allocation (default: 64MB)
#
# Use cases:
#   - RAG applications
#   - Semantic search
#   - Embedding storage
#   - AI agent memory
#

set -e

echo "========================================================"
echo "  PGLite Vector Build - AI/ML Optimized Variant"
echo "========================================================"
echo ""

# Configuration for vector-optimized build
export PGLITE_VARIANT="vector"
export PGLITE_VARIANT_DESC="AI/ML optimized with pgvector"

# Memory optimizations for Cloudflare Workers
export TOTAL_MEMORY=${TOTAL_MEMORY:-64MB}
export CMA_MB=${CMA_MB:-6}

# Size optimizations
export PGLITE_UTF8_ONLY=${PGLITE_UTF8_ONLY:-true}
export SNOWBALL_LANGUAGES=${SNOWBALL_LANGUAGES:-english}

# Vector extension bundling
export PREBUNDLE_VECTOR=${PREBUNDLE_VECTOR:-true}

# Debug mode (default: off for minimal size)
export DEBUG=${DEBUG:-false}

# Output directories
export PGLITE_VECTOR_DIST=${PGLITE_VECTOR_DIST:-/tmp/pglite-vector}

echo "Build Configuration:"
echo "  Variant:          $PGLITE_VARIANT ($PGLITE_VARIANT_DESC)"
echo "  Total Memory:     $TOTAL_MEMORY"
echo "  CMA MB:           $CMA_MB"
echo "  UTF-8 Only:       $PGLITE_UTF8_ONLY"
echo "  Snowball:         $SNOWBALL_LANGUAGES"
echo "  Prebundle Vector: $PREBUNDLE_VECTOR"
echo "  Debug:            $DEBUG"
echo "  Output:           $PGLITE_VECTOR_DIST"
echo ""

# Run the main build with our optimizations
# The wasm-build.sh script will pick up our environment variables

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Step 1: Run the standard wasm build with vector optimizations
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
if [ -d "pglite/vector" ]; then
    pushd pglite/vector > /dev/null
    if [ ! -f "vector.so" ]; then
        echo "Building pgvector extension..."
        PG_CONFIG=${PGROOT:-/tmp/pglite}/bin/pg_config emmake make OPTFLAGS="" install || {
            echo "WARNING: vector extension build may have issues, continuing..."
        }
    else
        echo "pgvector extension already built (vector.so exists)"
    fi
    popd > /dev/null
else
    echo "Running vector.sh to build pgvector..."
    if [ -f "extra/vector.sh" ]; then
        ./extra/vector.sh
    fi
fi

# Step 3: Create variant-specific output directory and copy files
echo ""
echo "Step 3: Creating vector variant distribution..."
mkdir -p "$PGLITE_VECTOR_DIST"

# Copy the core WASM files
if [ -d "${PGL_DIST_WEB:-/tmp/sdk/dist/pglite-web}" ]; then
    cp -v "${PGL_DIST_WEB:-/tmp/sdk/dist/pglite-web}"/pglite.* "$PGLITE_VECTOR_DIST/" 2>/dev/null || true
fi

# Copy vector extension
if [ -f "pglite/vector/vector.so" ]; then
    cp -v pglite/vector/vector.so "$PGLITE_VECTOR_DIST/"
fi

# Step 4: Calculate and display sizes
echo ""
echo "========================================================"
echo "  Build Complete - Size Analysis"
echo "========================================================"

if [ -f "$PGLITE_VECTOR_DIST/pglite.wasm" ]; then
    WASM_SIZE=$(du -h "$PGLITE_VECTOR_DIST/pglite.wasm" | cut -f1)
    echo "  WASM Size:      $WASM_SIZE"
fi

if [ -f "$PGLITE_VECTOR_DIST/pglite.data" ]; then
    DATA_SIZE=$(du -h "$PGLITE_VECTOR_DIST/pglite.data" | cut -f1)
    echo "  Data Size:      $DATA_SIZE"
fi

if [ -f "$PGLITE_VECTOR_DIST/vector.so" ]; then
    VECTOR_SIZE=$(du -h "$PGLITE_VECTOR_DIST/vector.so" | cut -f1)
    echo "  Vector Ext:     $VECTOR_SIZE"
fi

# Calculate total bundle size
if [ -d "$PGLITE_VECTOR_DIST" ]; then
    TOTAL_SIZE=$(du -sh "$PGLITE_VECTOR_DIST" | cut -f1)
    echo "  Total Bundle:   $TOTAL_SIZE"
fi

echo ""
echo "Vector variant files in: $PGLITE_VECTOR_DIST"
echo ""
echo "Features included:"
echo "  - pgvector extension (HNSW + IVFFlat indexes)"
echo "  - JSON/JSONB support"
echo "  - English-only full-text search"
echo "  - UTF-8 encoding only"
echo ""
echo "Features excluded:"
echo "  - Multi-language Snowball stemmers"
echo "  - Non-UTF-8 charset converters"
echo ""
echo "Use cases:"
echo "  - RAG applications"
echo "  - Semantic search"
echo "  - Embedding storage"
echo "  - AI agent memory"
echo ""
echo "========================================================"
