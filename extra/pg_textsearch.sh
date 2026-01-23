#!/bin/bash
#
# Build script for pg_textsearch extension for PGLite WASM
#
# WASM Compatibility Notes:
# - Uses shared memory (shmem) and LWLocks - these work in single-connection mode
# - Has parallel build support but amcanparallel=false for scans
# - SpinLocks and pg_atomic_* operations used in parallel build
# - Registry uses dshash (dynamic shared hash) in shared memory
#

. wasm-build/extension.sh

pushd $PG_EXTRA/pg_textsearch
    # Build the extension using emmake for WASM compilation
    # OPTFLAGS="" disables architecture-specific optimizations (SSE/NEON)
    PG_CONFIG=${PGROOT}/bin/pg_config emmake make OPTFLAGS="" install || exit 1
popd
