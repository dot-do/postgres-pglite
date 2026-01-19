# PGLite Vector Variant

A specialized PGLite build optimized for AI/ML workloads, particularly vector similarity search and RAG (Retrieval-Augmented Generation) applications.

## Overview

The vector variant (`pglite-vector`) is a minimal PostgreSQL-in-WASM build that prioritizes:
- Vector similarity operations with pgvector
- JSON/JSONB for metadata storage
- English full-text search
- Small bundle size for edge deployment

## Size Targets

| Component | Standard Build | Vector Variant | Savings |
|-----------|---------------|----------------|---------|
| WASM Binary | ~8.5 MB | ~6-7 MB | ~1.5-2.5 MB |
| Data Bundle | ~4.7 MB | ~3-4 MB | ~1-1.7 MB |
| Total Bundle | ~13 MB | ~10-11 MB | ~2-3 MB |
| Memory Footprint | ~80 MB | ~55-65 MB | ~15-25 MB |

### Size Optimizations Applied

1. **English-Only Snowball Stemmers** (~500KB+ savings)
   - Removes 23+ language stemmers
   - Keeps English and Porter stemmers for FTS

2. **UTF-8 Only Encoding** (~1.8MB savings)
   - Removes charset converters for Asian/legacy encodings
   - Suitable for applications using UTF-8 throughout

3. **Reduced Debug Info** (varies)
   - Release build with size optimization flags

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
| `DEBUG` | `false` | Enable debug symbols |
| `TOTAL_MEMORY` | `64MB` | Maximum memory allocation |
| `CMA_MB` | `6` | Contiguous memory area size in MB |
| `PGLITE_UTF8_ONLY` | `true` | UTF-8 only charset support |
| `SNOWBALL_LANGUAGES` | `english` | Snowball stemmer languages |
| `PREBUNDLE_VECTOR` | `true` | Pre-bundle vector extension |

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

## Related Issues

- postgres-4box.3: Create pglite-vector build variant (AI/ML optimized)
- postgres-4box: Build variants epic

## License

Same as PGLite (PostgreSQL License)
