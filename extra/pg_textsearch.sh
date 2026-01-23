#!/bin/bash

. wasm-build/extension.sh

pushd $PG_EXTRA
    if [ -d pg_textsearch ]
    then
        echo using local pg_textsearch
    else
        echo "pg_textsearch directory not found - it should be a submodule in extra/"
        exit 1
    fi
popd

pushd $PG_EXTRA/pg_textsearch
    # path for wasm-shared already set to (pwd:pg build dir)/bin
    # OPTFLAGS="" turns off arch optim (sse/neon).
    PG_CONFIG=${PGROOT}/bin/pg_config emmake make OPTFLAGS="" install || exit 22
popd
