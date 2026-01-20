# PGLite Vector Variant

A specialized PGLite build optimized for AI/ML workloads, particularly vector similarity search and RAG (Retrieval-Augmented Generation) applications.

## Overview

The vector variant (`pglite-vector`) is a PostgreSQL-in-WASM build that prioritizes:
- Vector similarity operations with pgvector extension
- JSON/JSONB for metadata storage alongside embeddings
- English full-text search for hybrid search capabilities
- Optimized bundle size for edge deployment

## Size Targets

| Component | Full Build | Vector Variant | Description |
|-----------|------------|----------------|-------------|
| WASM Binary | ~8.5 MB | ~6.2 MB | Core PostgreSQL engine |
| Data Bundle | ~4.7 MB | ~2.9 MB | LZ4 compressed filesystem |
| Vector Extension | ~45 KB | ~45 KB | pgvector 0.8.0 tarball |
| JS Runtime | ~395 KB | ~350 KB | Emscripten module loader |
| **Total Bundle** | **~13.6 MB** | **~9.5 MB** | Complete package |
| Memory Footprint | ~80 MB | ~60-65 MB | After initialization |

### Size Optimizations Applied

The vector variant applies the following optimizations to achieve the ~9.5MB target:

1. **English-Only Snowball Stemmers** (~500KB savings)
   - Removes 26+ language stemmers (Arabic, French, German, Spanish, etc.)
   - Keeps English stemmer for hybrid FTS+vector search

2. **UTF-8 Only Encoding** (~1.8MB savings)
   - Removes charset converters for Asian/legacy encodings (Big5, EUC-CN, EUC-JP, etc.)
   - UTF-8 is standard for modern AI/ML applications

3. **Size-Optimized Compilation** (~1.5MB savings)
   - `-Oz` optimization for smallest binary size
   - Link-time optimization (LTO) for dead code elimination
   - No debug symbols in release builds
   - Closure compiler for JS minification

4. **Selective Extension Inclusion**
   - Only pgvector extension included
   - Excludes pgcrypto (~1.1MB), contrib extensions

## Features Included

### pgvector Extension
- **HNSW Index**: Hierarchical Navigable Small World graphs for fast ANN search
- **IVFFlat Index**: Inverted File with Flat compression
- **Distance Functions**:
  - L2 distance (`<->`)
  - Cosine distance (`<=>`)
  - Inner product (`<#>`)
- **Vector Types**:
  - `vector(n)` - Dense vectors up to 16,000 dimensions
  - `halfvec(n)` - Half-precision vectors
  - `sparsevec(n)` - Sparse vectors

### JSON/JSONB Support
Full JSON/JSONB support for storing metadata alongside vectors:
- Containment operators (`@>`, `<@`)
- Existence operators (`?`, `?|`, `?&`)
- Path queries (`->`, `->>`, `#>`, `#>>`)
- Indexing with GIN

### Full-Text Search (English)
English-only text search capabilities:
- `to_tsvector('english', text)`
- `to_tsquery('english', query)`
- `ts_rank()` for relevance scoring
- GiST and GIN index support

## Features Excluded

To achieve smaller bundle size, the following are excluded or minimized:

- **Multi-language Snowball stemmers**: Arabic, Armenian, Basque, Catalan, Danish, Dutch, Finnish, French, German, Greek, Hindi, Hungarian, Indonesian, Irish, Italian, Lithuanian, Nepali, Norwegian, Portuguese, Romanian, Russian, Serbian, Spanish, Swedish, Tamil, Turkish, Yiddish
- **Non-UTF-8 charset converters**: Big5, EUC-CN, EUC-JP, EUC-KR, etc.
- **Geometric types**: `point`, `box`, `circle`, `polygon`, etc. (use pgvector instead)
- **Network types**: `inet`, `cidr`, `macaddr`
- **Replication features**: Logical decoding, replication slots

## Use Cases

### RAG Applications
```sql
-- Store document chunks with embeddings
CREATE TABLE documents (
  id SERIAL PRIMARY KEY,
  content TEXT,
  embedding vector(1536),
  metadata JSONB
);

CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);

-- Retrieve relevant chunks
SELECT content, metadata
FROM documents
WHERE metadata @> '{"source": "docs"}'
ORDER BY embedding <=> $query_embedding
LIMIT 5;
```

### Semantic Search
```sql
-- Hybrid search combining FTS and vector similarity
SELECT
  content,
  ts_rank(to_tsvector('english', content), query) as text_rank,
  1 - (embedding <=> $query_embedding) as semantic_score
FROM documents,
  plainto_tsquery('english', $search_text) query
WHERE to_tsvector('english', content) @@ query
ORDER BY (text_rank * 0.3 + (1 - (embedding <=> $query_embedding)) * 0.7) DESC;
```

### AI Agent Memory
```sql
-- Store conversation history with embeddings
CREATE TABLE agent_memory (
  id SERIAL PRIMARY KEY,
  conversation_id TEXT,
  role TEXT CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT,
  embedding vector(384),
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  metadata JSONB
);

-- Retrieve relevant past interactions
SELECT content, role, timestamp
FROM agent_memory
WHERE conversation_id = $conv_id
  OR embedding <-> $current_embedding < 0.3
ORDER BY timestamp DESC
LIMIT 10;
```

## Building

```bash
# Standard vector build
cd postgres-pglite
./build-pglite-vector.sh

# Debug build
DEBUG=true ./build-pglite-vector.sh

# Custom memory limit
TOTAL_MEMORY=128MB ./build-pglite-vector.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DEBUG` | `false` | Enable debug symbols (increases size significantly) |
| `TOTAL_MEMORY` | `64MB` | Initial memory allocation |
| `CMA_MB` | `8` | Contiguous memory area for wire protocol (MB) |
| `PGLITE_UTF8_ONLY` | `true` | UTF-8 only charset support |
| `SNOWBALL_LANGUAGES` | `english` | Snowball stemmer languages |
| `PREBUNDLE_VECTOR` | `true` | Pre-bundle vector extension |
| `PGLITE_VECTOR_DIST` | `/tmp/pglite-vector` | Output directory for build |

## Testing

Run the vector variant tests:

```bash
cd packages/pglite
pnpm test tests/pglite-vector-variant.test.ts
```

## Compatibility

The vector variant is designed for:
- Cloudflare Workers (128MB memory limit)
- Edge functions
- Browser-based applications
- Embedded AI assistants

## Build Requirements

Building the vector variant requires:
- Docker (for consistent Emscripten SDK environment)
- ~10GB disk space for build artifacts
- ~30 minutes for full build

The build uses the Emscripten SDK to compile PostgreSQL to WebAssembly with the trampoline fix for Cloudflare Workers compatibility.

## Related Issues

- postgres-q0t8: Build and validate vector variant with pgvector
- postgres-4box.3: Create pglite-vector build variant (AI/ML optimized)
- postgres-4box: Build variants epic

## License

Same as PGLite (PostgreSQL License)
