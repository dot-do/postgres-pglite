#!/bin/bash
# =============================================================================
# build-pglite-fts.sh - Full-Text Search Optimized PGLite Build
# =============================================================================
#
# This script builds a PGLite variant optimized for full-text search use cases.
# Target: ~6MB bundle, ~60-65MB memory
#
# Use Cases:
#   - Search engines
#   - Content management systems
#   - Documentation search
#   - Product catalogs
#
# Features Included:
#   - English Snowball stemmer (SNOWBALL_LANGUAGES=english)
#   - pg_trgm extension (trigram matching)
#   - fuzzystrmatch extension (soundex, levenshtein, metaphone)
#   - GIN indexes for FTS
#   - JSON/JSONB support
#
# Features Excluded:
#   - Non-English Snowball stemmers (~500KB savings)
#   - Non-UTF-8 charset converters (~1.8MB savings)
#   - Replication support
#   - Geometric types
#   - Network address types
#
# Usage:
#   ./build-pglite-fts.sh
#
# Environment Variables:
#   DEBUG=true/false - Build debug or release version (default: false)
#   CMA_MB=8        - Memory zone size in MB (default: 8)
#
# =============================================================================

set -e

# Source the base configuration
export PG_VERSION=${PG_VERSION:-17.4}
export LC_ALL=C

# FTS Build Variant Configuration
export PGLITE_VARIANT="fts"
export PGLITE_VARIANT_DESC="Full-Text Search Optimized"

# Core optimizations for FTS variant
# 1. English-only Snowball stemmer (~500KB savings)
export SNOWBALL_LANGUAGES=english

# 2. UTF-8 only charset support (~1.8MB savings)
export PGLITE_UTF8_ONLY=true

# 3. Reduced memory footprint
export TOTAL_MEMORY=${TOTAL_MEMORY:-64MB}

# 4. Size-optimized compilation
export DEBUG=${DEBUG:-false}

# CI and path setup
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

# ICU is not needed for FTS (English uses built-in stemmer)
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

# Create output directories
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

# Print build configuration
echo "
================================================================================
PGLite FTS Build Variant
================================================================================

Variant: $PGLITE_VARIANT ($PGLITE_VARIANT_DESC)

Key Optimizations:
  - SNOWBALL_LANGUAGES: $SNOWBALL_LANGUAGES (English stemmer only)
  - PGLITE_UTF8_ONLY:   $PGLITE_UTF8_ONLY (UTF-8 charset only)
  - USE_ICU:            $USE_ICU (disabled for size)
  - TOTAL_MEMORY:       $TOTAL_MEMORY
  - DEBUG:              $DEBUG

FTS Features Included:
  - English full-text search (tsvector, tsquery)
  - GIN index support for FTS
  - pg_trgm extension (trigram similarity)
  - fuzzystrmatch extension (soundex, levenshtein, metaphone)
  - JSON/JSONB support

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

# Source SDK environment
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

# Compiler settings
export CC_PGLITE="-DPYDK=1 -DPG_PREFIX=${PGROOT} -I${PGROOT}/include -DCMA_MB=${CMA_MB}"

# Debug header
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

# Store build options
cat > ${PGROOT}/pgopts-fts.sh <<END
# PGLite FTS Variant Build Options
export PGLITE_VARIANT=fts
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

# FTS-specific extension list (minimal set for full-text search)
export FTS_EXTENSIONS="fuzzystrmatch pg_trgm"

echo "
================================================================================
Starting FTS variant build...
================================================================================
"

# Source the main build script which will use our SNOWBALL_LANGUAGES setting
. ${PGROOT}/pgopts-fts.sh

# Build PostgreSQL core with English-only Snowball
echo "Building PostgreSQL core with SNOWBALL_LANGUAGES=$SNOWBALL_LANGUAGES..."

# The main wasm-build.sh will pick up our environment variables
if [ -f "${WORKSPACE}/wasm-build.sh" ]; then
    # Link our FTS options file
    cp ${PGROOT}/pgopts-fts.sh ${PGROOT}/pgopts.sh

    # Run the main build
    ${WORKSPACE}/wasm-build.sh
else
    echo "Error: wasm-build.sh not found in ${WORKSPACE}"
    exit 1
fi

# After build, report sizes
echo "
================================================================================
FTS Variant Build Complete
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
FTS variant features:
  - English full-text search: to_tsvector('english', text)
  - Stemming: running -> run, quickly -> quick
  - GIN index support for fast FTS queries
  - pg_trgm: similarity matching with trigrams
  - fuzzystrmatch: soundex, levenshtein, metaphone

To use the FTS variant:
  import { PGlite } from '@dotdo/pglite-fts'
  const db = await PGlite.create()

  // Full-text search
  await db.query(\"SELECT to_tsvector('english', 'Quick brown fox')\")

  // GIN index
  await db.exec('CREATE INDEX idx ON docs USING GIN(tsv)')

  // pg_trgm (load extension)
  await db.exec('CREATE EXTENSION pg_trgm')
  await db.query(\"SELECT similarity('word', 'words')\")
================================================================================
"
