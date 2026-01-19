#!/bin/bash
#
# build-pglite-full.sh - Build the complete PGlite variant with all features
#
# This creates the full-featured PGlite build including:
# - All 27 Snowball language stemmers
# - All contrib extensions (50+)
# - All charset converters
# - Full XML/XSLT support
# - All PostgreSQL types (geometric, network, etc.)
# - UUID support
# - pgcrypto with OpenSSL
#
# Target: ~8.5MB WASM bundle, ~81MB runtime memory
#
# Use cases:
# - Maximum compatibility
# - Multi-language applications
# - Complex queries requiring all PostgreSQL features
# - Reference/benchmark build
#
# Usage:
#   ./build-pglite-full.sh
#
# Environment Variables:
#   DEBUG=true      - Build with debug symbols (default: false)
#   TOTAL_MEMORY    - Override initial memory allocation (default: 128MB)
#

set -e

# Ensure we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "
================================================================================
                    PGlite FULL Build - All Features Included
================================================================================

Building full-featured PGlite with:
  - All 27 Snowball language stemmers
  - All 50+ contrib extensions
  - All charset converters (UTF-8, Latin, CJK, etc.)
  - Full XML/XSLT support
  - All PostgreSQL types
  - UUID support with OSSP
  - pgcrypto with OpenSSL
  - Maximum compatibility mode

"

# ============================================================================
# FULL BUILD CONFIGURATION
# ============================================================================

# Allow debug mode override
export DEBUG=${DEBUG:-false}

# Full mode - all features enabled
export PGLITE_FULL=true

# All Snowball stemmers (27 languages)
# arabic armenian basque catalan danish dutch english finnish french german
# greek hindi hungarian indonesian irish italian lithuanian nepali norwegian
# portuguese romanian russian serbian spanish swedish tamil turkish yiddish
export SNOWBALL_LANGUAGES="arabic armenian basque catalan danish dutch english finnish french german greek hindi hungarian indonesian irish italian lithuanian nepali norwegian portuguese romanian russian serbian spanish swedish tamil turkish yiddish"

# Include ALL contrib extensions
export SKIP_CONTRIB=false

# Full charset support - include all converters
export PGLITE_UTF8_ONLY=false

# Maximum memory for full workloads
export TOTAL_MEMORY=${TOTAL_MEMORY:-128MB}

# Larger CMA zone for complex queries
export CMA_MB=${CMA_MB:-16}

# Balance between size and performance for full build
export COPTS="-O2 -flto"
export LOPTS="-O2 -flto --closure=0 -sASSERTIONS=0"

# ============================================================================
# CONFIGURE OPTIONS FOR FULL BUILD
# ============================================================================

# Enable all optional features
export PGLITE_FULL_CONFIGURE_OPTS="
--with-zlib
--with-libxml
--with-libxslt
--with-uuid=ossp
--with-openssl
"

echo "
Configuration:
  DEBUG=$DEBUG
  PGLITE_FULL=$PGLITE_FULL
  PGLITE_UTF8_ONLY=$PGLITE_UTF8_ONLY
  SKIP_CONTRIB=$SKIP_CONTRIB
  TOTAL_MEMORY=$TOTAL_MEMORY
  CMA_MB=$CMA_MB
  COPTS=$COPTS

Full build includes:

Snowball Stemmers (27 languages):
  Arabic, Armenian, Basque, Catalan, Danish, Dutch, English, Finnish,
  French, German, Greek, Hindi, Hungarian, Indonesian, Irish, Italian,
  Lithuanian, Nepali, Norwegian, Portuguese, Romanian, Russian, Serbian,
  Spanish, Swedish, Tamil, Turkish, Yiddish

Contrib Extensions (50+):
  amcheck, bloom, btree_gin, btree_gist, citext, cube, dblink,
  earthdistance, fuzzystrmatch, hstore, intarray, isn, lo, ltree,
  pg_trgm, pgcrypto, pgrowlocks, pgstattuple, seg, tablefunc,
  tcn, tsm_system_rows, tsm_system_time, unaccent, uuid-ossp, xml2...

Extra PGlite Extensions:
  - vector (pgvector) - Vector similarity search
  - pg_ivm - Incremental View Maintenance
  - pg_uuidv7 - UUIDv7 generation
  - pg_hashids - Hashids encoding
  - pgtap - Unit testing framework

PostgreSQL Types:
  - All numeric types (int2, int4, int8, float4, float8, numeric)
  - All text types (char, varchar, text, name)
  - All date/time types (date, time, timestamp, timestamptz, interval)
  - JSON and JSONB with all operators
  - Arrays and ranges
  - Geometric types (point, line, box, circle, polygon, path)
  - Network types (inet, cidr, macaddr, macaddr8)
  - UUID
  - XML
  - Bit strings
  - Bytea
  - Enums
  - Composite types

Charset Converters:
  UTF-8, Latin1-15, Windows-125x, ISO-8859-x, EUC-JP, EUC-KR, EUC-CN,
  EUC-TW, SJIS, GB18030, GBK, BIG5, JOHAB, UHC, and more...
"

# ============================================================================
# BUILD
# ============================================================================

# Run the main wasm build with full configuration
if [ -f ./wasm-build.sh ]; then
    echo "Starting full build..."
    ./wasm-build.sh "$@"
else
    # Fall back to the main build script
    if [ -f ./build-pglite.sh ]; then
        echo "Starting full build via build-pglite.sh..."
        ./build-pglite.sh "$@"
    else
        echo "Error: No build script found in $SCRIPT_DIR"
        exit 1
    fi
fi

# ============================================================================
# POST-BUILD SIZE REPORT
# ============================================================================

echo "
================================================================================
                    PGlite FULL Build - Size Report
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
    DATA_BYTES=$(stat -f%z "${WEB_DIST}/pglite.data" 2>/dev/null || stat -c%s "${WEB_DIST}/pglite.data" 2>/dev/null)
    echo "Data bundle size: $DATA_SIZE ($DATA_BYTES bytes, LZ4 compressed)"
fi

if [ -f "${WEB_DIST}/pglite.js" ]; then
    JS_SIZE=$(du -h "${WEB_DIST}/pglite.js" | cut -f1)
    echo "JS wrapper size:  $JS_SIZE"
fi

# Calculate extension count
EXT_COUNT=$(ls "${WEB_DIST}/"*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
if [ "$EXT_COUNT" -gt 0 ]; then
    echo "Extensions:       $EXT_COUNT extension bundles"
fi

echo "
================================================================================

Full build complete! Output files in: ${WEB_DIST}

This is the reference build with maximum compatibility.
Use this variant when you need:
  - Multi-language text search (27 languages)
  - All PostgreSQL data types
  - Maximum extension compatibility
  - Full charset support

For smaller builds, consider:
  - pglite-tiny:   ~3MB   - Core SQL only
  - pglite-json:   ~4MB   - JSON/JSONB optimized
  - pglite-vector: ~5MB   - AI/ML vector search
  - pglite-fts:    ~6MB   - English full-text search

================================================================================
"
