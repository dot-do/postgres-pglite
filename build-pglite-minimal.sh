#!/bin/bash
#
# build-pglite-minimal.sh - Build a minimal PGLite variant (core SQL only)
#
# =============================================================================
# OVERVIEW
# =============================================================================
#
# This creates a minimal PGLite build optimized for core SQL functionality:
# - Full SQL executor (SELECT, INSERT, UPDATE, DELETE, JOIN, etc.)
# - All standard index types (btree, hash, GIN, GiST)
# - All core PostgreSQL types (numeric, text, date/time, JSON, arrays)
# - Transactions and ACID compliance
# - Parameterized queries
# - UTF-8 only charset support (saves ~1.8MB)
# - English-only Snowball stemmer (saves ~500KB)
# - NO extensions (no FTS, no pgvector, no pgcrypto)
#
# =============================================================================
# TARGET SIZE AND MEMORY
# =============================================================================
#
# Target: ~5MB WASM bundle, ~50-55MB runtime memory
#
# Size breakdown:
#   - WASM binary: ~5MB (includes core executor, parser, planner, types)
#   - Data bundle: ~2MB (LZ4 compressed - share/postgresql, lib, password)
#   - JS runtime:  ~100KB (Emscripten module loader)
#   - Total static: ~7MB
#
# Memory footprint:
#   - Initial:     32MB (Emscripten heap)
#   - After init:  ~50-55MB
#   - Growth:      ALLOW_MEMORY_GROWTH enabled, but stays within 128MB
#
# =============================================================================
# USE CASES
# =============================================================================
#
# Ideal for:
# - General-purpose SQL queries
# - CRUD operations
# - Cloudflare Workers deployments (128MB limit)
# - Edge computing with minimal footprint
# - Local-first applications
# - Offline data storage
# - Lightweight analytics
#
# NOT ideal for:
# - Full-text search (use pglite-fts)
# - Vector similarity search (use pglite-vector)
# - Cryptographic operations (use pglite-full)
# - Multi-language text processing (use pglite-full)
#
# =============================================================================
# USAGE
# =============================================================================
#
#   ./build-pglite-minimal.sh          # Standard minimal build
#   DEBUG=true ./build-pglite-minimal.sh  # Debug build with symbols
#
# =============================================================================
# ENVIRONMENT VARIABLES
# =============================================================================
#
#   DEBUG=true/false  - Build debug or release version (default: false)
#   TOTAL_MEMORY      - Override initial memory allocation (default: 64MB)
#   CMA_MB            - Wire query zone size in MB (default: 8)
#
# =============================================================================

set -e

# Ensure we're in the right directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "
================================================================================
                    PGLite MINIMAL Build - Core SQL Only
================================================================================

Building minimal PGLite with core SQL functionality:
  - Full SQL executor (DML, DDL, joins, subqueries)
  - All index types (btree, hash, GIN, GiST, BRIN)
  - Core PostgreSQL types (numeric, text, date/time, JSON, arrays)
  - Transactions and ACID compliance
  - Parameterized queries and prepared statements
  - UTF-8 only charset support (~1.8MB savings)
  - English-only stemmer (~500KB savings)
  - NO contrib extensions
  - Optimized for size (-Oz with LTO)

"

# =============================================================================
# MINIMAL BUILD CONFIGURATION
# =============================================================================

# Force release mode for size optimization (unless explicitly debugging)
export DEBUG=${DEBUG:-false}

# Variant identification
export PGLITE_VARIANT="minimal"
export PGLITE_VARIANT_DESC="Core SQL only (no extensions)"

# UTF-8 only - excludes all non-UTF-8 charset converters
# This saves ~1.8MB since we don't need Latin, CJK, or other converters
# UTF-8 is the standard for modern applications anyway
export PGLITE_UTF8_ONLY=true

# English-only Snowball stemmer
# This saves ~500KB by excluding 27+ language stemmers
# Provides basic text search stemming without the full FTS overhead
export SNOWBALL_LANGUAGES=english

# Skip ALL contrib extensions
# This is the key difference from other builds - no extensions at all
# Saves ~2-3MB depending on which extensions would otherwise be included
export SKIP_CONTRIB=true

# Memory configuration optimized for Cloudflare Workers 128MB limit
# We leave headroom for queries and data
export TOTAL_MEMORY=${TOTAL_MEMORY:-64MB}

# CMA (Contiguous Memory Area) for wire protocol
# 8MB is sufficient for most queries while staying under memory limits
export CMA_MB=${CMA_MB:-8}

# Size optimization compiler flags
# -Oz: Optimize for smallest binary size (over speed)
# -flto: Link-time optimization for dead code elimination
# -fno-exceptions: No C++ exceptions (PostgreSQL is C)
export COPTS="-Oz -flto -fno-exceptions"
export LOPTS="-Oz -flto -fno-exceptions --closure=0 -sASSERTIONS=0"

# =============================================================================
# CONFIGURE OPTIONS FOR MINIMAL BUILD
# =============================================================================

# Keep essential features, disable unnecessary ones
# We KEEP:
#   - zlib: Useful for TOAST compression of large values
#   - uuid: OSSP UUID generation is useful and small
# We DISABLE:
#   - libxml/libxslt: XML processing is rarely needed for minimal use
#   - NLS: Native Language Support for error messages
#   - ICU: Full Unicode collation (basic collation still works)

export PGLITE_MINIMAL_CONFIGURE_OPTS="
--with-zlib
--with-uuid=ossp
--without-libxml
--without-libxslt
--disable-nls
--without-icu
"

# =============================================================================
# DISPLAY CONFIGURATION
# =============================================================================

echo "
Configuration:
  PGLITE_VARIANT:     $PGLITE_VARIANT
  DEBUG:              $DEBUG
  PGLITE_UTF8_ONLY:   $PGLITE_UTF8_ONLY
  SNOWBALL_LANGUAGES: $SNOWBALL_LANGUAGES
  SKIP_CONTRIB:       $SKIP_CONTRIB
  TOTAL_MEMORY:       $TOTAL_MEMORY
  CMA_MB:             $CMA_MB

Compiler Flags:
  COPTS: $COPTS
  LOPTS: $LOPTS

===============================================================================
INCLUDED FEATURES (Core SQL)
===============================================================================

SQL Executor:
  + SELECT, INSERT, UPDATE, DELETE
  + JOINs (INNER, LEFT, RIGHT, FULL, CROSS)
  + Subqueries and CTEs (WITH clause)
  + Window functions (ROW_NUMBER, RANK, etc.)
  + Aggregate functions (COUNT, SUM, AVG, etc.)
  + UNION, INTERSECT, EXCEPT
  + CASE expressions
  + Prepared statements and parameterized queries

Index Types:
  + B-tree (default, range queries, equality)
  + Hash (equality only, faster for exact matches)
  + GIN (inverted index for arrays, JSONB)
  + GiST (generalized search tree)
  + BRIN (block range index for large tables)

Data Types:
  + Numeric: smallint, integer, bigint, decimal, numeric, real, double
  + Character: char, varchar, text
  + Date/Time: date, time, timestamp, timestamptz, interval
  + Boolean: boolean
  + Binary: bytea
  + UUID: uuid (with OSSP generator)
  + JSON: json, jsonb (with all operators)
  + Arrays: int[], text[], etc.
  + Ranges: int4range, daterange, etc.
  + Network: inet, cidr, macaddr (built-in, not extension)
  + Geometric: point, line, box, circle, polygon (built-in)

Transactions:
  + BEGIN, COMMIT, ROLLBACK
  + SAVEPOINT and nested transactions
  + Isolation levels (READ COMMITTED, REPEATABLE READ, SERIALIZABLE)
  + ACID compliance

Schema Management:
  + CREATE/ALTER/DROP TABLE, VIEW, INDEX
  + Sequences (SERIAL, BIGSERIAL, IDENTITY)
  + Constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK, NOT NULL)
  + GENERATED columns
  + Partitioning

===============================================================================
EXCLUDED FEATURES
===============================================================================

Contrib Extensions (all excluded):
  - pgcrypto (encryption functions)
  - pgvector (vector similarity search)
  - pg_trgm (trigram text similarity)
  - fuzzystrmatch (soundex, levenshtein)
  - hstore (key-value store)
  - ltree (hierarchical labels)
  - intarray (integer array functions)
  - earthdistance (geographic calculations)
  - tablefunc (crosstab, pivot)
  - uuid-ossp (UUID generation functions)
  - citext (case-insensitive text)
  - btree_gin, btree_gist (combined indexes)
  - ... and 40+ other contrib extensions

Language Support:
  - Non-English Snowball stemmers (26 languages)
  - Non-UTF-8 charset converters (Latin, CJK, etc.)
  - ICU collation

External Libraries:
  - libxml/libxslt (XML processing)
  - OpenSSL (cryptographic functions)

"

# =============================================================================
# BUILD
# =============================================================================

# Run the main wasm build with minimal configuration
if [ -f ./wasm-build.sh ]; then
    echo "Starting minimal build..."
    echo ""
    ./wasm-build.sh "$@"
else
    echo "Error: wasm-build.sh not found in $SCRIPT_DIR"
    exit 1
fi

# =============================================================================
# POST-BUILD SIZE REPORT
# =============================================================================

echo "
================================================================================
                    PGLite MINIMAL Build - Size Report
================================================================================
"

DIST_DIR="/tmp/sdk/dist"
WEB_DIST="${DIST_DIR}/pglite-web"

if [ -f "${WEB_DIST}/pglite.wasm" ]; then
    WASM_SIZE=$(du -h "${WEB_DIST}/pglite.wasm" | cut -f1)
    # Try both BSD (macOS) and GNU (Linux) stat syntax
    WASM_BYTES=$(stat -f%z "${WEB_DIST}/pglite.wasm" 2>/dev/null || stat -c%s "${WEB_DIST}/pglite.wasm" 2>/dev/null)
    echo "WASM bundle size: $WASM_SIZE ($WASM_BYTES bytes)"

    # Check if we hit our ~5MB target
    if [ -n "$WASM_BYTES" ]; then
        WASM_MB=$((WASM_BYTES / 1048576))
        if [ "$WASM_MB" -le 5 ]; then
            echo "  [OK] Within ~5MB target"
        else
            echo "  [WARNING] Exceeds ~5MB target - consider reviewing build flags"
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

Minimal build complete! Output files in: ${WEB_DIST}

Files produced:
  - pglite.wasm  - WebAssembly binary (core PostgreSQL)
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

  // Core SQL operations
  await pg.exec('CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT)')
  await pg.exec(\"INSERT INTO users (name) VALUES ('Alice')\")
  const result = await pg.query('SELECT * FROM users WHERE id = \$1', [1])

Memory Budget (128MB Cloudflare Workers):
  - Static bundle:  ~7MB (WASM + data + JS)
  - After init:     ~50-55MB
  - Available:      ~70-75MB for queries and results

Comparison with other variants:
  - pglite-tiny:    ~3MB   - Absolute minimum, basic types only
  - pglite-minimal: ~5MB   - Core SQL, all types, no extensions (THIS BUILD)
  - pglite-json:    ~4MB   - JSON/JSONB optimized
  - pglite-fts:     ~6MB   - Full-text search with English stemmer
  - pglite-vector:  ~5MB   - AI/ML with pgvector
  - pglite-full:    ~8.5MB - All features and extensions

================================================================================
"
