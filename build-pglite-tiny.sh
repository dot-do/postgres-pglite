#!/bin/bash
#
# build-pglite-tiny.sh - Build the smallest possible PGlite variant
#
# This creates a minimal PGlite build with only core SQL functionality:
# - Core SQL executor (SELECT, INSERT, UPDATE, DELETE)
# - btree indexes only
# - Basic PostgreSQL types (int, text, bool, timestamp, date)
# - Minimal system catalogs
# - UTF-8 only charset support (saves ~1.8MB)
# - No extensions (saves ~2-3MB)
# - No Snowball stemmers (saves ~500KB)
#
# Target: ~2.5-3MB WASM bundle, ~35-40MB runtime memory
#
# Use cases:
# - Simple key-value style queries
# - Edge caching / lookup tables
# - Memory-constrained environments (Cloudflare Workers)
# - Benchmarking baseline
#
# Usage:
#   ./build-pglite-tiny.sh
#
# Environment Variables:
#   DEBUG=true      - Build with debug symbols (default: false)
#   TOTAL_MEMORY    - Override initial memory allocation (default: 32MB)
#

set -e

# Ensure we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "
================================================================================
                    PGlite TINY Build - Minimal Footprint
================================================================================

Building the smallest possible PGlite with:
  - Core SQL executor only
  - btree indexes
  - Basic PostgreSQL types
  - UTF-8 only charset support
  - NO extensions
  - NO Snowball stemmers
  - NO JSON (if possible)
  - NO XML/XSLT
  - NO geometric/network types
  - Optimized for minimum size (-Oz)

"

# ============================================================================
# TINY BUILD CONFIGURATION
# ============================================================================

# Force release mode for maximum size optimization
export DEBUG=${DEBUG:-false}

# Enable UTF-8 only mode - excludes all charset converters
# This saves ~1.8MB in the final bundle
export PGLITE_UTF8_ONLY=true

# TINY mode - disables maximum features
export PGLITE_TINY=true

# No Snowball stemmers at all
export SNOWBALL_LANGUAGES=""

# Skip ALL contrib extensions
export SKIP_CONTRIB=true

# Minimal memory configuration
export TOTAL_MEMORY=${TOTAL_MEMORY:-32MB}

# Minimal CMA zone
export CMA_MB=${CMA_MB:-4}

# Maximum size optimization flags
export COPTS="-Oz -flto -fno-exceptions -fno-rtti"
export LOPTS="-Oz -flto -fno-exceptions --closure=1 -sASSERTIONS=0 -sEVAL_CTORS=2"

# ============================================================================
# CONFIGURE OPTIONS FOR TINY BUILD
# ============================================================================

# Disable as many features as possible
export PGLITE_TINY_CONFIGURE_OPTS="
--without-zlib
--without-libxml
--without-libxslt
--without-uuid
--without-openssl
--disable-nls
--disable-thread-safety
"

echo "
Configuration:
  DEBUG=$DEBUG
  PGLITE_TINY=$PGLITE_TINY
  PGLITE_UTF8_ONLY=$PGLITE_UTF8_ONLY
  SNOWBALL_LANGUAGES=(none)
  SKIP_CONTRIB=$SKIP_CONTRIB
  TOTAL_MEMORY=$TOTAL_MEMORY
  CMA_MB=$CMA_MB
  COPTS=$COPTS

Tiny build features:
  + Core SQL (SELECT, INSERT, UPDATE, DELETE)
  + btree indexes
  + Basic types (int4, int8, text, varchar, bool, date, timestamp)
  + Parameterized queries
  + Transactions
  + PL/pgSQL (minimal)

Explicitly excluded:
  - ALL Snowball stemmers
  - ALL contrib extensions
  - ALL charset converters (except UTF-8)
  - XML/XSLT support
  - UUID generation
  - zlib compression
  - OpenSSL
  - Geometric types (if possible)
  - Network types (if possible)
"

# ============================================================================
# BUILD
# ============================================================================

# Run the main wasm build with tiny configuration
if [ -f ./wasm-build.sh ]; then
    echo "Starting tiny build..."
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
                    PGlite TINY Build - Size Report
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

Tiny build complete! Output files in: ${WEB_DIST}

Features included:
  + Core SQL executor
  + btree indexes
  + Basic types (int, text, bool, date, timestamp)
  + Parameterized queries
  + Transactions
  + UTF-8 text encoding

Features excluded:
  - ALL language stemmers
  - ALL extensions
  - ALL charset converters (except UTF-8)
  - XML/XSLT
  - UUID
  - zlib
  - OpenSSL

Example usage:
  -- Create a simple lookup table
  CREATE TABLE cache (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    expires_at TIMESTAMP
  );

  -- Insert with parameterized query
  INSERT INTO cache (key, value, expires_at) VALUES (\$1, \$2, \$3);

  -- Lookup
  SELECT value FROM cache WHERE key = \$1 AND expires_at > NOW();

This variant is ideal for:
  - Key-value style storage
  - Simple CRUD operations
  - Memory-constrained environments
  - Baseline benchmarking

================================================================================
"
