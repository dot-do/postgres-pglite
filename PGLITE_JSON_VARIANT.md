# PGLite JSON Variant

JSON/JSONB optimized PGLite build for document-style database workloads.

## Overview

The JSON variant is a PGLite build specifically designed for applications that work primarily with JSON and JSONB data types. It includes all JSONB operators, functions, and indexing capabilities while optimizing for document database use cases similar to MongoDB.

**Target Metrics:**
- Bundle size: ~8MB (WASM)
- Memory usage: ~50-60MB after initialization
- Data bundle: ~3-4MB (LZ4 compressed)

## Use Cases

- Document databases / MongoDB-style applications
- Configuration storage systems
- Flexible schema applications
- Event sourcing with JSON payloads
- API response caching
- User preferences and settings storage
- Content management systems
- Real-time collaborative applications

## Features Included

### Core JSON/JSONB Support

The JSON variant includes full PostgreSQL JSON and JSONB functionality:

#### Data Types
- `json` - Text-based JSON storage (preserves whitespace and key order)
- `jsonb` - Binary JSON storage (efficient queries and indexing)

#### Containment Operators
| Operator | Description | Example |
|----------|-------------|---------|
| `@>` | Contains | `'{"a":1}'::jsonb @> '{"a":1}'` |
| `<@` | Contained by | `'{"a":1}'::jsonb <@ '{"a":1,"b":2}'` |

#### Existence Operators
| Operator | Description | Example |
|----------|-------------|---------|
| `?` | Key exists | `'{"a":1}'::jsonb ? 'a'` |
| `?|` | Any key exists | `'{"a":1}'::jsonb ?| array['a','b']` |
| `?&` | All keys exist | `'{"a":1,"b":2}'::jsonb ?& array['a','b']` |

#### Path Operators
| Operator | Description | Example |
|----------|-------------|---------|
| `->` | Get JSON object field | `'{"a":1}'::jsonb -> 'a'` |
| `->>` | Get JSON field as text | `'{"a":1}'::jsonb ->> 'a'` |
| `#>` | Get JSON object at path | `'{"a":{"b":1}}'::jsonb #> '{a,b}'` |
| `#>>` | Get JSON value at path as text | `'{"a":{"b":1}}'::jsonb #>> '{a,b}'` |

#### JSONB Path Queries (jsonpath)
| Operator | Description | Example |
|----------|-------------|---------|
| `@?` | Path exists | `data @? '$.items[*] ? (@.price > 10)'` |
| `@@` | Path predicate | `'{"price":150}'::jsonb @@ '$.price > 100'` |

#### JSONB Functions
- **Construction**: `jsonb_build_object()`, `jsonb_build_array()`, `to_jsonb()`
- **Extraction**: `jsonb_extract_path()`, `jsonb_each()`, `jsonb_array_elements()`
- **Modification**: `jsonb_set()`, `jsonb_insert()`, `jsonb_strip_nulls()`
- **Aggregation**: `jsonb_agg()`, `jsonb_object_agg()`
- **Utility**: `jsonb_pretty()`, `jsonb_typeof()`, `jsonb_array_length()`

### Index Support

- **GIN indexes** with `jsonb_ops` - Supports all JSONB operators
- **GIN indexes** with `jsonb_path_ops` - Optimized for containment queries
- **btree_gin extension** - Combined B-tree/GIN indexes for mixed queries

### Extensions

- `btree_gin` - Combined scalar and JSONB indexes
- `hstore` - Key-value store type (simpler alternative to JSONB)
- `uuid-ossp` - UUID generation (via configure)

### Text Search

- English Snowball stemmer for full-text search within JSON documents
- GIN indexes for tsvector columns

## Features Excluded (for size optimization)

- Non-English Snowball stemmers (26+ languages)
- ICU collation
- pgvector (vector similarity)
- pgcrypto (encryption)
- Geographic/geometric extensions
- Many contrib extensions

## Building

```bash
cd packages/pglite/postgres-pglite

# Build with defaults (release mode)
./build-pglite-json.sh

# Build debug version with symbols
DEBUG=true ./build-pglite-json.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| DEBUG | false | Build debug or release version |
| TOTAL_MEMORY | 64MB | Initial memory allocation |
| CMA_MB | 8 | Wire query zone size in MB |

## Usage

### Cloudflare Workers

```typescript
import { PGlite } from '@dotdo/pglite'
import pgliteWasm from './pglite.wasm'
import pgliteData from './pglite.data'

const pg = await PGlite.create({
  wasmModule: pgliteWasm,
  fsBundle: new Blob([pgliteData]),
})

// Create a documents collection
await pg.exec(`
  CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
  )
`)

// Create GIN index for efficient queries
await pg.exec('CREATE INDEX idx_documents_data ON documents USING GIN (data)')
```

### Document Operations

```typescript
// Insert documents
await pg.query(
  'INSERT INTO documents (data) VALUES ($1)',
  [{ type: 'user', name: 'John', email: 'john@example.com', tags: ['admin'] }]
)

// Find by type (MongoDB-style)
const users = await pg.query(`
  SELECT data FROM documents WHERE data @> '{"type": "user"}'
`)

// Find by nested value
const admins = await pg.query(`
  SELECT data FROM documents WHERE data @> '{"tags": ["admin"]}'
`)

// Update document fields
await pg.exec(`
  UPDATE documents
  SET data = jsonb_set(data, '{lastLogin}', '"2024-01-20"'),
      updated_at = now()
  WHERE data @> '{"email": "john@example.com"}'
`)

// Project specific fields
const names = await pg.query(`
  SELECT data->>'name' as name, data->>'email' as email
  FROM documents
  WHERE data @> '{"type": "user"}'
`)
```

### JSONB Path Queries

```typescript
// Find items with price > 10
const expensive = await pg.query(`
  SELECT * FROM orders
  WHERE data @? '$.items[*] ? (@.price > 10)'
`)

// Extract all item names
const itemNames = await pg.query(`
  SELECT jsonb_path_query_array(data, '$.items[*].name') as names
  FROM orders
`)
```

### Full-Text Search on JSON

```typescript
// Create table with generated tsvector from JSON fields
await pg.exec(`
  CREATE TABLE articles (
    id SERIAL PRIMARY KEY,
    data JSONB NOT NULL,
    tsv tsvector GENERATED ALWAYS AS (
      to_tsvector('english',
        coalesce(data->>'title', '') || ' ' ||
        coalesce(data->>'body', '')
      )
    ) STORED
  );

  CREATE INDEX idx_articles_tsv ON articles USING GIN (tsv);
`)

// Search within JSON content
const results = await pg.query(`
  SELECT data->>'title' as title
  FROM articles
  WHERE tsv @@ to_tsquery('english', 'postgresql & database')
`)
```

## Performance Tips

1. **Use GIN indexes** - Always create GIN indexes on JSONB columns that will be queried
2. **Use `jsonb_path_ops`** - For containment-only queries, this operator class is smaller and faster
3. **Prefer JSONB over JSON** - JSONB is faster for queries and supports indexing
4. **Use generated tsvector columns** - Pre-compute text search vectors for JSON content
5. **Project only needed fields** - Use `->` and `->>` to extract only required data
6. **Batch inserts** - Use multi-row INSERT for better performance

## Memory Budget (128MB Cloudflare Workers)

```
128 MB (Worker limit)
- 8-10 MB (WASM binary)
- 3-4 MB (data bundle)
- ~20 MB (PostgreSQL initialization)
- ~20 MB (shared_buffers + WAL)
= ~70-75 MB available for queries and results
```

## Size Comparison

| Build Variant | WASM Size | Use Case |
|--------------|-----------|----------|
| pglite-tiny | ~3MB | Minimal, basic types only |
| pglite-minimal | ~5MB | Core SQL, no extensions |
| pglite-json | ~8MB | JSON/JSONB optimized (this build) |
| pglite-fts | ~6MB | Full-text search focused |
| pglite-vector | ~5MB | AI/ML with pgvector |
| pglite-full | ~8.5MB | All features and extensions |

## Testing

Run the JSON variant tests:

```bash
cd packages/pglite
npx vitest run tests/pglite-json-variant.test.ts
```

The test suite covers:
- JSONB containment operators (@>, <@)
- JSONB existence operators (?, ?|, ?&)
- JSONB path operators (->, ->>, #>, #>>)
- JSONB path queries (@?, @@)
- GIN index creation and queries
- JSONB modification functions
- Document database use cases
- English text search on JSON content

## Related Issues

- postgres-kotv: Build and validate JSON variant
