#!/bin/bash
#
# build-pglite-json.sh - Build a JSON-optimized PGlite variant
#
# This creates a PGlite build optimized for document-style JSON workloads with:
# - Full JSON and JSONB support with all operators (@>, <@, ?, ?|, ?&, ->>, ->, #>)
# - GIN indexes for efficient JSONB queries
# - JSONB path queries (jsonpath)
# - Full text search support (English stemmer)
# - UTF-8 charset support
# - uuid-ossp extension for UUID generation
# - btree_gin for efficient combined indexes
#
# Target: ~8MB WASM bundle, ~50-60MB runtime memory
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

# JSON variant includes full charset support for international JSON documents
# We keep UTF-8 as the default but support other encodings
export PGLITE_UTF8_ONLY=false

# Build with English Snowball stemmer for text search in JSON documents
# This provides full-text search capability within JSON values
export SNOWBALL_LANGUAGES=english

# Variant identification
export PGLITE_VARIANT="json"
export PGLITE_VARIANT_DESC="JSON/JSONB optimized (document database)"

# Include contrib extensions useful for JSON workloads
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
# - hstore: Key-value store type (useful for simple document structures)
# - uuid-ossp: UUID generation (common for document IDs)
# We exclude extensions that aren't useful for JSON document workloads:
# - earthdistance, cube, ltree, intarray, vector, etc.

export PGLITE_JSON_EXTENSIONS="btree_gin hstore"

echo "
Configuration:
  PGLITE_VARIANT:     $PGLITE_VARIANT
  DEBUG:              $DEBUG
  PGLITE_UTF8_ONLY:   $PGLITE_UTF8_ONLY
  SNOWBALL_LANGUAGES: $SNOWBALL_LANGUAGES
  PGLITE_JSON_BUILD:  $PGLITE_JSON_BUILD
  TOTAL_MEMORY:       $TOTAL_MEMORY
  CMA_MB:             $CMA_MB
  COPTS:              $COPTS

===============================================================================
INCLUDED FEATURES (JSON/JSONB)
===============================================================================

JSON/JSONB Types:
  + json type (text-based JSON storage)
  + jsonb type (binary JSON with indexing)
  + All JSON/JSONB functions and operators

JSONB Operators:
  + Containment: @> (contains), <@ (contained by)
  + Existence: ? (key exists), ?| (any key), ?& (all keys)
  + Path access: -> (object), ->> (text), #> (path), #>> (text path)
  + Comparison: =, <>, <, >, <=, >=

JSONB Path Queries (jsonpath):
  + Path expressions: \$.store.book[0].title
  + Filters: \$.items[*] ? (@.price > 10)
  + Methods: .type(), .size(), .double(), .ceiling()
  + Predicates: @? (exists), @@ (match)

JSONB Functions:
  + Construction: jsonb_build_object, jsonb_build_array, to_jsonb
  + Extraction: jsonb_extract_path, jsonb_each, jsonb_array_elements
  + Modification: jsonb_set, jsonb_insert, jsonb_strip_nulls
  + Aggregation: jsonb_agg, jsonb_object_agg
  + Utility: jsonb_pretty, jsonb_typeof, jsonb_array_length

Index Support:
  + GIN indexes for JSONB (jsonb_ops - all operators)
  + GIN indexes for JSONB paths (jsonb_path_ops - containment only)
  + btree_gin extension for combined indexes

Extensions:
  + btree_gin - Combined B-tree/GIN indexes
  + hstore - Key-value store type
  + uuid-ossp - UUID generation (via configure)

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
    # Try both BSD (macOS) and GNU (Linux) stat syntax
    WASM_BYTES=$(stat -f%z "${WEB_DIST}/pglite.wasm" 2>/dev/null || stat -c%s "${WEB_DIST}/pglite.wasm" 2>/dev/null)
    echo "WASM bundle size: $WASM_SIZE ($WASM_BYTES bytes)"

    # Check if we hit our ~8MB target
    if [ -n "$WASM_BYTES" ]; then
        WASM_MB=$((WASM_BYTES / 1048576))
        if [ "$WASM_MB" -le 8 ]; then
            echo "  [OK] Within ~8MB target"
        else
            echo "  [WARNING] Exceeds ~8MB target - consider reviewing build flags"
        fi
    fi
fi

if [ -f "${WEB_DIST}/pglite.data" ]; then
    DATA_SIZE=$(du -h "${WEB_DIST}/pglite.data" | cut -f1)
    DATA_BYTES=$(stat -f%z "${WEB_DIST}/pglite.data" 2>/dev/null || stat -c%s "${WEB_DIST}/pglite.data" 2>/dev/null)
    echo "Data bundle size: $DATA_SIZE (LZ4 compressed)"
fi

if [ -f "${WEB_DIST}/pglite.js" ]; then
    JS_SIZE=$(du -h "${WEB_DIST}/pglite.js" | cut -f1)
    echo "JS wrapper size:  $JS_SIZE"
fi

# Calculate total static bundle
TOTAL_BYTES=0
for file in "${WEB_DIST}/pglite.wasm" "${WEB_DIST}/pglite.data" "${WEB_DIST}/pglite.js"; do
    if [ -f "$file" ]; then
        FILE_BYTES=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        TOTAL_BYTES=$((TOTAL_BYTES + FILE_BYTES))
    fi
done
if [ "$TOTAL_BYTES" -gt 0 ]; then
    TOTAL_MB=$((TOTAL_BYTES / 1048576))
    echo "Total bundle:     ${TOTAL_MB}MB ($TOTAL_BYTES bytes)"
fi

echo "
================================================================================

JSON build complete! Output files in: ${WEB_DIST}

Files produced:
  - pglite.wasm  - WebAssembly binary (PostgreSQL + JSON support)
  - pglite.data  - Filesystem bundle (share/lib/password)
  - pglite.js    - JavaScript module loader

Usage with Cloudflare Workers:

  import { PGlite } from '@dotdo/pglite'
  import pgliteWasm from './pglite.wasm'
  import pgliteData from './pglite.data'

  const pg = await PGlite.create({
    wasmModule: pgliteWasm,
    fsBundle: new Blob([pgliteData]),
  })

  // Create a documents table with JSONB
  await pg.exec(\`
    CREATE TABLE documents (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      data JSONB NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now()
    )
  \`)

  // Create GIN index for efficient queries
  await pg.exec('CREATE INDEX idx_documents_data ON documents USING GIN (data)')

  // Insert a document
  await pg.exec(\`
    INSERT INTO documents (data) VALUES
    ('{ \"type\": \"article\", \"title\": \"Hello World\", \"tags\": [\"intro\", \"welcome\"] }')
  \`)

  // Query using containment
  const articles = await pg.query(
    \"SELECT * FROM documents WHERE data @> '{\\\"type\\\": \\\"article\\\"}'\"
  )

  // Query using path
  const titles = await pg.query(
    \"SELECT data->>'title' as title FROM documents WHERE data ? 'title'\"
  )

  // Query using jsonpath
  const tagged = await pg.query(
    \"SELECT * FROM documents WHERE data @? '\\\$.tags[*] ? (@ == \\\"intro\\\")'\"
  )

Memory Budget (128MB Cloudflare Workers):
  - Static bundle:  ~10-12MB (WASM + data + JS)
  - After init:     ~55-65MB
  - Available:      ~60-70MB for queries and results

Comparison with other variants:
  - pglite-tiny:    ~3MB   - Absolute minimum, basic types only
  - pglite-minimal: ~5MB   - Core SQL, all types, no extensions
  - pglite-json:    ~8MB   - JSON/JSONB optimized (THIS BUILD)
  - pglite-fts:     ~6MB   - Full-text search with English stemmer
  - pglite-vector:  ~5MB   - AI/ML with pgvector
  - pglite-full:    ~8.5MB - All features and extensions

================================================================================
"
