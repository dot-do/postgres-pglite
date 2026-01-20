#!/bin/bash
# =============================================================================
# build-pglite-standard.sh - Standard PGLite Build with English Full-Text Search
# =============================================================================
#
# This script builds the "standard" PGLite variant - the recommended default
# for most applications. It provides a good balance between features and size.
#
# Target: ~6MB WASM bundle, ~60MB runtime memory
#
# Use Cases:
#   - General-purpose web applications
#   - Content management systems
#   - Documentation and blog platforms
#   - E-commerce product catalogs
#   - Any English-language application needing search
#
# Features Included:
#   - Full PostgreSQL SQL support
#   - English Snowball stemmer for full-text search
#   - pg_trgm extension (trigram similarity matching)
#   - fuzzystrmatch extension (soundex, levenshtein, metaphone)
#   - GIN indexes for efficient FTS
#   - JSON/JSONB support
#   - All standard PostgreSQL types
#   - PL/pgSQL procedural language
#
# Features Excluded (for smaller bundle size):
#   - Non-English Snowball stemmers (~500KB savings)
#   - Non-UTF-8 charset converters (~1.8MB savings)
#   - Replication support (not needed for embedded use)
#   - pgvector (use pglite-vector variant for AI/ML)
#
# Usage:
#   ./build-pglite-standard.sh
#
# Environment Variables:
#   DEBUG=true/false - Build debug or release version (default: false)
#   TOTAL_MEMORY     - Override memory allocation (default: 64MB)
#   CMA_MB           - Memory zone size in MB (default: 8)
#
# =============================================================================

set -e

# Source the base configuration
export PG_VERSION=${PG_VERSION:-17.4}
export LC_ALL=C

# Standard Build Variant Configuration
export PGLITE_VARIANT="standard"
export PGLITE_VARIANT_DESC="Standard build with English FTS"

# =============================================================================
# STANDARD BUILD OPTIMIZATIONS
# =============================================================================

# 1. English-only Snowball stemmer (~500KB savings over full)
#    Supports: to_tsvector('english', ...), ts_rank, ts_headline
export SNOWBALL_LANGUAGES=english

# 2. UTF-8 only charset support (~1.8MB savings)
#    Modern apps should use UTF-8 exclusively
export PGLITE_UTF8_ONLY=true

# 3. Memory configuration optimized for Cloudflare Workers (128MB limit)
export TOTAL_MEMORY=${TOTAL_MEMORY:-64MB}

# 4. Size-optimized compilation for production
export DEBUG=${DEBUG:-false}

# =============================================================================
# CI AND PATH SETUP
# =============================================================================

export CI=${CI:-false}
export PORTABLE=${PORTABLE:-$(pwd)/wasm-build}
export SDKROOT=${SDKROOT:-/tmp/sdk}

# Systems default may not be in path
export ZIC=${ZIC:-/usr/sbin/zic}

if [ -x $ZIC ]; then
    export GETZIC=false
else
    export GETZIC=true
fi

# Data transfer zone (wire query size + result size) + 2
# Expressed in EMSDK MB, max is 13MB on emsdk 3.1.74+
export CMA_MB=${CMA_MB:-8}

export WORKSPACE=${GITHUB_WORKSPACE:-$(pwd)}
export PGROOT=${PGROOT:-/tmp/pglite}
export WEBROOT=${WEBROOT:-/tmp/web}

export PG_BUILD=${BUILD:-/tmp/sdk/build}
    export PG_BUILD_DUMPS=${PG_BUILD}/dumps
    export PGL_BUILD_NATIVE=${PG_BUILD}/pglite-native

export PG_DIST=${DIST:-/tmp/sdk/dist}
    export PG_DIST_EXT=${PG_DIST}/extensions-emsdk

    export PGL_DIST_JS=${PG_DIST}/pglite-js
    export PGL_DIST_LINK=${PG_DIST}/pglite-link

    export PGL_DIST_NATIVE=${PG_DIST}/pglite-native
    export PGL_DIST_C=${PG_DIST}/pglite-native
    export PGL_DIST_WEB=${PG_DIST}/pglite-web

export PGUSER=${PGUSER:-postgres}

# ICU is not needed for standard build (English uses built-in stemmer)
export USE_ICU=false

# WASI/Emscripten selection
export WASI=${WASI:-false}
export NATIVE=${NATIVE:-false}

# Build type
if $WASI; then
    BUILD=wasi
else
    BUILD=emscripten
fi

# Compiler optimizations
if $DEBUG; then
    export COPTS="-O2 -g3 --no-wasm-opt"
    export LOPTS=${LOPTS:-"-O2 -g3 --no-wasm-opt -sASSERTIONS=1"}
else
    # Size-optimized build for production
    export COPTS="-Oz -flto -fno-exceptions"
    export LOPTS=${LOPTS:-"-Oz -flto -fno-exceptions --closure=0 -sASSERTIONS=0"}
fi

export BUILD
export BUILD_PATH=${PG_BUILD}/${BUILD}
export PG_EXTRA=${PG_BUILD}/extra-${BUILD}

# =============================================================================
# CREATE OUTPUT DIRECTORIES
# =============================================================================

DIST_ALL="${PGROOT}/bin ${PG_DIST} ${PG_DIST_EXT} ${PG_BUILD_DUMPS} ${PGL_DIST_JS} ${PGL_BUILD_NATIVE}"
DIST_ALL="$DIST_ALL ${PGL_DIST_NATIVE} ${PGL_DIST_WEB} ${PGL_DIST_C} ${PG_EXTRA}"
DIST_ALL="$DIST_ALL ${PGL_DIST_LINK}/imports ${PGL_DIST_LINK}/exports"

if mkdir -p $DIST_ALL; then
    echo "Checking for valid prefix ${PGROOT} ${PG_DIST}"
else
    sudo mkdir -p $DIST_ALL
    sudo chown $(whoami) -R $DIST_ALL
fi

export PGDATA=${PGROOT}/base

chmod +x ${PORTABLE}/*.sh 2>/dev/null || true
[ -d ${PORTABLE}/extra ] && chmod +x ${PORTABLE}/extra/*.sh 2>/dev/null || true

# =============================================================================
# PRINT BUILD CONFIGURATION
# =============================================================================

echo "
================================================================================
PGLite Standard Build Variant
================================================================================

Variant: $PGLITE_VARIANT ($PGLITE_VARIANT_DESC)

This is the recommended default build for most applications.

Key Optimizations:
  - SNOWBALL_LANGUAGES: $SNOWBALL_LANGUAGES (English stemmer only)
  - PGLITE_UTF8_ONLY:   $PGLITE_UTF8_ONLY (UTF-8 charset only)
  - USE_ICU:            $USE_ICU (disabled for size)
  - TOTAL_MEMORY:       $TOTAL_MEMORY
  - DEBUG:              $DEBUG

Included Features:
  - Full PostgreSQL SQL support (SELECT, INSERT, UPDATE, DELETE, JOIN, etc.)
  - English full-text search (tsvector, tsquery, GIN indexes)
  - pg_trgm extension (trigram similarity)
  - fuzzystrmatch extension (soundex, levenshtein, metaphone)
  - JSON/JSONB support with all operators
  - All standard PostgreSQL types
  - PL/pgSQL procedural language
  - btree, hash, and GIN indexes

Excluded Features (for smaller size):
  - Non-English Snowball stemmers (use pglite-full for multi-language)
  - Non-UTF-8 charset converters
  - pgvector (use pglite-vector for AI/ML workloads)

Build Settings:
  - COPTS: $COPTS
  - LOPTS: $LOPTS
  - CMA_MB: $CMA_MB
  - PG_VERSION: $PG_VERSION

Output Directories:
  - PGROOT: $PGROOT
  - PG_DIST: $PG_DIST
  - PGL_DIST_WEB: $PGL_DIST_WEB

================================================================================
"

# =============================================================================
# SOURCE SDK ENVIRONMENT
# =============================================================================

pushd ${SDKROOT}
    if ${WASI}; then
        . wasisdk/wasisdk_env.sh
        if ${PORTABLE}/sdk.sh; then
            echo "$PORTABLE : sdk check passed (wasi)"
        fi
    else
        if which emcc; then
            echo "emcc found in PATH=$PATH"
        else
            . ${SDKROOT}/wasm32-bi-emscripten-shell.sh
        fi

        if ${PORTABLE}/sdk.sh; then
            echo "$PORTABLE : sdk check passed (emscripten)"
        else
            echo "emsdk failed"; exit 1
        fi

        export PG_LINK=${PG_LINK:-$(which emcc)}
    fi
popd

# =============================================================================
# COMPILER SETTINGS
# =============================================================================

export CC_PGLITE="-DPYDK=1 -DPG_PREFIX=${PGROOT} -I${PGROOT}/include -DCMA_MB=${CMA_MB}"

# =============================================================================
# DEBUG HEADER
# =============================================================================

mkdir -p ${PGROOT}/include
if $DEBUG; then
    export PGDEBUG=""
    cat > ${PGROOT}/include/pg_debug.h << END
#ifndef I_PGDEBUG
#define I_PGDEBUG
#define WASM_USERNAME "$PGUSER"
#define PGDEBUG 1
#define PDEBUG(string) { fputs(string, stderr); fputs("\r\n", stderr); }
#define JSDEBUG(string) {EM_ASM({ console.log(string); });}
#define ADEBUG(string) { PDEBUG(string); JSDEBUG(string) }
#endif
END
else
    export PGDEBUG=""
    cat > ${PGROOT}/include/pg_debug.h << END
#ifndef I_PGDEBUG
#define I_PGDEBUG
#define WASM_USERNAME "$PGUSER"
#define PDEBUG(string)
#define JSDEBUG(string)
#define ADEBUG(string)
#define PGDEBUG 0
#endif
END
fi

mkdir -p ${PGROOT}/include/postgresql/server
for dest in ${PGROOT}/include ${PGROOT}/include/postgresql ${PGROOT}/include/postgresql/server; do
    [ -f $dest/pg_debug.h ] || cp ${PGROOT}/include/pg_debug.h $dest/
done

# =============================================================================
# STORE BUILD OPTIONS
# =============================================================================

cat > ${PGROOT}/pgopts-standard.sh <<END
# PGLite Standard Variant Build Options
export PGLITE_VARIANT=standard
export SNOWBALL_LANGUAGES=english
export PGLITE_UTF8_ONLY=true
export CMA_MB=$CMA_MB
export TOTAL_MEMORY=$TOTAL_MEMORY
export CC_PGLITE="$CC_PGLITE"
export CI=$CI
export PORTABLE=$PORTABLE
export SDKROOT=$SDKROOT
export WORKSPACE=$WORKSPACE
export PGROOT=$PGROOT
export WEBROOT=$WEBROOT
export PG_BUILD=$PG_BUILD
export PG_DIST=$PG_DIST
export DEBUG=$DEBUG
export USE_ICU=$USE_ICU
export PGUSER=$PGUSER
export BUILD=$BUILD
export BUILD_PATH=$BUILD_PATH
export COPTS="$COPTS"
export LOPTS="$LOPTS"
export PGDEBUG="$PGDEBUG"
END

# Standard variant extension list (common extensions for general use)
export STANDARD_EXTENSIONS="fuzzystrmatch pg_trgm"

echo "
================================================================================
Starting Standard variant build...
================================================================================
"

# Source the build options
. ${PGROOT}/pgopts-standard.sh

# =============================================================================
# BUILD POSTGRESQL CORE
# =============================================================================

echo "Building PostgreSQL core with SNOWBALL_LANGUAGES=$SNOWBALL_LANGUAGES..."

# The main wasm-build.sh will pick up our environment variables
if [ -f "${WORKSPACE}/wasm-build.sh" ]; then
    # Link our standard options file
    cp ${PGROOT}/pgopts-standard.sh ${PGROOT}/pgopts.sh

    # Run the main build
    ${WORKSPACE}/wasm-build.sh
else
    echo "Error: wasm-build.sh not found in ${WORKSPACE}"
    exit 1
fi

# =============================================================================
# POST-BUILD REPORT
# =============================================================================

echo "
================================================================================
PGLite Standard Build Complete
================================================================================
"

if [ -f "${PGL_DIST_WEB}/pglite.wasm" ]; then
    WASM_SIZE=$(du -h "${PGL_DIST_WEB}/pglite.wasm" | cut -f1)
    echo "WASM Size: $WASM_SIZE"
fi

if [ -f "${PGL_DIST_WEB}/pglite.data" ]; then
    DATA_SIZE=$(du -h "${PGL_DIST_WEB}/pglite.data" | cut -f1)
    echo "Data Size: $DATA_SIZE"
fi

echo "
================================================================================
Standard Variant Features - Quick Reference
================================================================================

Full-Text Search:
  -- Create a tsvector column
  ALTER TABLE articles ADD COLUMN tsv tsvector;
  UPDATE articles SET tsv = to_tsvector('english', title || ' ' || body);

  -- Create GIN index for fast search
  CREATE INDEX idx_articles_tsv ON articles USING GIN(tsv);

  -- Search with ranking
  SELECT title, ts_rank(tsv, query) AS rank
  FROM articles, to_tsquery('english', 'database & search') query
  WHERE tsv @@ query
  ORDER BY rank DESC;

Trigram Similarity (pg_trgm):
  -- Load extension
  CREATE EXTENSION pg_trgm;

  -- Fuzzy search
  SELECT * FROM products WHERE name % 'laptip';  -- finds 'laptop'

  -- Similarity score
  SELECT similarity('word', 'words');  -- returns ~0.5

Fuzzy String Matching (fuzzystrmatch):
  -- Load extension
  CREATE EXTENSION fuzzystrmatch;

  -- Soundex (phonetic matching)
  SELECT soundex('Robert'), soundex('Rupert');  -- both 'R163'

  -- Levenshtein distance
  SELECT levenshtein('kitten', 'sitting');  -- returns 3

  -- Metaphone
  SELECT metaphone('programming', 10);  -- 'PRKRMNK'

================================================================================

To use the Standard variant:
  import { PGlite } from '@dotdo/pglite-standard'
  const db = await PGlite.create()

Comparison with other variants:
  - pglite-tiny:     ~3MB  - Core SQL only, no extensions
  - pglite-json:     ~4MB  - JSON/JSONB optimized
  - pglite-standard: ~6MB  - English FTS + common extensions (THIS BUILD)
  - pglite-vector:   ~5MB  - AI/ML with pgvector
  - pglite-full:     ~9MB  - All languages, all extensions

================================================================================
"
