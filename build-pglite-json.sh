#!/bin/bash
#
# build-pglite-json.sh - Build a JSON-optimized PGlite variant
#
# This creates a PGlite build optimized for document-style JSON workloads with:
# - Full JSON and JSONB support with all operators (@>, <@, ?, ?|, ?&, ->>, ->, #>)
# - GIN indexes for efficient JSONB queries
# - JSONB path queries (jsonpath)
# - English-only text search stemmer (saves ~500KB)
# - UTF-8 only charset support (saves ~1.8MB)
# - Excludes Snowball stemmers for non-English languages
# - Excludes non-UTF-8 charset converters
#
# Target: ~4MB WASM bundle, ~45-50MB runtime memory
#
# Use cases:
# - Document databases / MongoDB-style applications
# - Configuration storage
# - Flexible schema applications
# - Event sourcing with JSON payloads
#
# Usage:
#   ./build-pglite-json.sh
#
# Environment Variables:
#   DEBUG=true      - Build with debug symbols (default: false)
#   TOTAL_MEMORY    - Override initial memory allocation (default: 64MB)
#

set -e

# Ensure we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "
================================================================================
                    PGlite JSON Build - Document Database Variant
================================================================================

Building JSON-optimized PGlite with:
  - Full JSONB support with containment operators (@>, <@)
  - JSONB existence operators (?, ?|, ?&)
  - JSONB path operators (->>, ->, #>, #>>)
  - JSONB path queries (jsonpath: @?, @@)
  - GIN indexes for JSONB
  - English-only text search stemmer
  - UTF-8 only charset support
  - Optimized for size (-Oz)

"

# ============================================================================
# JSON BUILD CONFIGURATION
# ============================================================================

# Force release mode for size optimization
export DEBUG=${DEBUG:-false}

# Enable UTF-8 only mode - excludes charset converters for non-UTF-8 encodings
# This saves ~1.8MB in the final bundle
# JSON is typically UTF-8 encoded so this is ideal
export PGLITE_UTF8_ONLY=true

# Build with English-only Snowball stemmer
# This saves ~500KB by excluding 27+ language stemmers
# Still useful for text search within JSON documents
export SNOWBALL_LANGUAGES=english

# Include btree_gin for combined indexes on scalar + JSONB
# Skip other extensions that aren't JSON-related
export SKIP_CONTRIB=false
export PGLITE_JSON_BUILD=true

# Memory configuration optimized for JSON document workloads
# JSON documents can be larger than scalar values, so we allocate more
export TOTAL_MEMORY=${TOTAL_MEMORY:-64MB}

# CMA zone for wire queries - JSON payloads may be larger
export CMA_MB=${CMA_MB:-8}

# Size optimization flags
export COPTS="-Oz -flto -fno-exceptions"
export LOPTS="-Oz -flto -fno-exceptions --closure=0 -sASSERTIONS=0"

# ============================================================================
# CONFIGURE OPTIONS FOR JSON BUILD
# ============================================================================

# We keep zlib for potential JSON compression use cases
# We disable features not needed for JSON workloads
export PGLITE_JSON_CONFIGURE_OPTS="
--without-libxslt
--disable-nls
"

# ============================================================================
# EXTENSIONS FOR JSON BUILD
# ============================================================================

# Extensions to include for JSON workloads:
# - btree_gin: Combined btree and GIN indexes (useful for mixed scalar + JSONB queries)
# We exclude extensions that aren't useful for JSON document workloads:
# - earthdistance, cube, ltree, intarray, etc.

export PGLITE_JSON_EXTENSIONS="btree_gin"

echo "
Configuration:
  DEBUG=$DEBUG
  PGLITE_UTF8_ONLY=$PGLITE_UTF8_ONLY
  SNOWBALL_LANGUAGES=$SNOWBALL_LANGUAGES
  PGLITE_JSON_BUILD=$PGLITE_JSON_BUILD
  TOTAL_MEMORY=$TOTAL_MEMORY
  CMA_MB=$CMA_MB
  COPTS=$COPTS

JSON-specific features:
  - JSONB binary storage format
  - GIN operator class for JSONB (jsonb_ops, jsonb_path_ops)
  - Containment operators (@>, <@)
  - Existence operators (?, ?|, ?&)
  - Path operators (->, ->>, #>, #>>)
  - JSONB path language (jsonpath)
  - JSONB aggregation (jsonb_agg, jsonb_object_agg)
  - JSONB set functions (jsonb_set, jsonb_insert)
"

# ============================================================================
# BUILD
# ============================================================================

# Run the main wasm build with JSON configuration
if [ -f ./wasm-build.sh ]; then
    echo "Starting JSON-optimized build..."
    ./wasm-build.sh "$@"
else
    echo "Error: wasm-build.sh not found in $SCRIPT_DIR"
    exit 1
fi

# ============================================================================
# POST-BUILD SIZE REPORT
# ============================================================================

echo "
================================================================================
                    PGlite JSON Build - Size Report
================================================================================
"

DIST_DIR="/tmp/sdk/dist"
WEB_DIST="${DIST_DIR}/pglite-web"

if [ -f "${WEB_DIST}/pglite.wasm" ]; then
    WASM_SIZE=$(du -h "${WEB_DIST}/pglite.wasm" | cut -f1)
    WASM_BYTES=$(stat -f%z "${WEB_DIST}/pglite.wasm" 2>/dev/null || stat -c%s "${WEB_DIST}/pglite.wasm" 2>/dev/null)
    echo "WASM bundle size: $WASM_SIZE ($WASM_BYTES bytes)"
fi

if [ -f "${WEB_DIST}/pglite.data" ]; then
    DATA_SIZE=$(du -h "${WEB_DIST}/pglite.data" | cut -f1)
    echo "Data bundle size: $DATA_SIZE (LZ4 compressed)"
fi

if [ -f "${WEB_DIST}/pglite.js" ]; then
    JS_SIZE=$(du -h "${WEB_DIST}/pglite.js" | cut -f1)
    echo "JS wrapper size:  $JS_SIZE"
fi

echo "
================================================================================

JSON build complete! Output files in: ${WEB_DIST}

JSON/JSONB Features included:
  + JSONB binary storage format
  + GIN indexes for JSONB queries
  + Containment: @> (contains), <@ (contained by)
  + Existence: ? (key exists), ?| (any key), ?& (all keys)
  + Path access: -> (object), ->> (text), #> (path), #>> (text path)
  + JSONB path queries: @? (exists), @@ (predicate)
  + Aggregation: jsonb_agg, jsonb_object_agg
  + Modification: jsonb_set, jsonb_insert, jsonb_strip_nulls
  + English text search (for searching within JSON text values)
  + btree_gin extension (combined scalar + JSONB indexes)

Features excluded for size:
  - 26+ language stemmers (only English included)
  - Non-UTF-8 charset converters
  - XSLT support
  - Native language support (NLS)
  - Most contrib extensions (cube, earthdistance, etc.)

Example usage:
  -- Create a documents table with JSONB
  CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    data JSONB NOT NULL
  );

  -- Create GIN index for efficient queries
  CREATE INDEX idx_documents_data ON documents USING GIN (data);

  -- Query using containment
  SELECT * FROM documents WHERE data @> '{\"type\": \"article\"}';

  -- Query using path
  SELECT data->>'title' FROM documents WHERE data ? 'title';

  -- Query using jsonpath
  SELECT * FROM documents WHERE data @? '\$.tags[*] ? (@ == \"important\")';

================================================================================
"
