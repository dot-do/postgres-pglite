# PGLite Tiny Variant

Absolute minimum PGLite build for the smallest possible footprint.

## Overview

The tiny variant (`pglite-tiny`) is the smallest possible PGLite build, stripped down to only the most essential SQL functionality. It provides the absolute minimum viable PostgreSQL implementation for extreme memory and size constraints.

**Target Metrics:**
- WASM size: ~3MB
- Data bundle: ~1.5MB (LZ4 compressed)
- Total bundle: <5MB (target: under 5MB)
- Memory usage: ~35-40MB

## Use Cases

- Key-value style queries
- Simple lookup tables
- Edge caching layers
- Memory-constrained environments (Cloudflare Workers 128MB)
- Baseline benchmarking
- Configuration storage
- Session data persistence
- Lightweight local storage

**NOT ideal for:**
- Complex queries with joins
- Full-text search
- JSON document storage
- Geometric or network operations
- Multi-language text processing

## Features Included

### SQL Executor (Basic)

**Data Manipulation:**
- SELECT (basic WHERE, ORDER BY, LIMIT)
- INSERT (single row, bulk)
- UPDATE (standard)
- DELETE (standard)

**Supported Clauses:**
- WHERE with basic operators (=, <, >, <=, >=, <>, LIKE, IN)
- ORDER BY
- LIMIT / OFFSET
- GROUP BY (basic)
- HAVING (basic)

### Index Types

| Index Type | Use Case | Operators |
|------------|----------|-----------|
| B-tree | Default, range queries, ordering | <, <=, =, >=, >, BETWEEN |

**Note:** Only B-tree indexes are fully optimized in the tiny build. Hash, GIN, GiST, and BRIN index code may be present but not tested or recommended.

### Data Types (Basic Only)

**Numeric:**
- `integer` (int4) - 4 bytes
- `bigint` (int8) - 8 bytes
- `boolean` - true/false/null

**Character:**
- `text` - unlimited length
- `varchar(n)` - variable-length with limit

**Date/Time:**
- `date` - date only
- `timestamp` - date and time
- `timestamptz` - date and time with timezone

### Transactions

- BEGIN/COMMIT/ROLLBACK
- Basic ACID compliance
- Single connection (optimized for DO isolation)

### Parameterized Queries

- Full support for $1, $2, ... parameters
- Protection against SQL injection
- Efficient query planning for repeated queries

### Schema Management

**Tables:**
- CREATE TABLE (basic)
- ALTER TABLE (basic)
- DROP TABLE

**Constraints:**
- PRIMARY KEY
- NOT NULL
- UNIQUE (basic)

**Indexes:**
- CREATE INDEX (B-tree only)
- DROP INDEX

## Features Excluded

### All Contrib Extensions

No extensions are included. This saves 2-3MB:
- No pgvector
- No pgcrypto
- No pg_trgm
- No fuzzystrmatch
- No hstore
- No ltree
- No uuid-ossp
- No citext
- No earthdistance
- No tablefunc
- No xml2

### All Snowball Stemmers

No language stemmers (saves ~500KB):
- No English stemmer
- No other language stemmers
- No full-text search support

### All Non-UTF-8 Charset Converters

UTF-8 only (saves ~1.8MB):
- No Latin encodings (ISO-8859-*, Windows-125*)
- No Asian encodings (Big5, GB18030, EUC-JP, EUC-KR, SJIS)
- No other legacy encodings

### Advanced SQL Features

- JOINs (possible but not optimized)
- Window functions
- Common Table Expressions (CTEs)
- Recursive queries
- MERGE statement
- Complex subqueries

### Data Types (Excluded)

- JSON/JSONB (possible but adds size)
- UUID
- Arrays
- Range types
- Geometric types (point, line, box, etc.)
- Network types (inet, cidr, macaddr)
- XML

### External Libraries

- zlib (no compression)
- libxml/libxslt (no XML)
- OpenSSL (no encryption)
- ICU (no collation)
- NLS (no internationalized error messages)

## Building

```bash
cd packages/pglite/postgres-pglite

# Standard tiny build (release mode, maximum size optimization)
./build-pglite-tiny.sh

# Debug build with symbols
DEBUG=true ./build-pglite-tiny.sh

# Custom memory allocation
TOTAL_MEMORY=32MB ./build-pglite-tiny.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DEBUG` | `false` | Build debug or release version |
| `TOTAL_MEMORY` | `32MB` | Initial memory allocation |
| `CMA_MB` | `4` | Wire query zone size (minimal) |
| `PGLITE_TINY` | `true` | Enable tiny build mode |
| `PGLITE_UTF8_ONLY` | `true` | UTF-8 only charset support |
| `SNOWBALL_LANGUAGES` | `""` | No Snowball stemmers |
| `SKIP_CONTRIB` | `true` | Skip all contrib extensions |

### Compiler Flags

```bash
COPTS="-Oz -flto -fno-exceptions -fno-rtti"
LOPTS="-Oz -flto -fno-exceptions --closure=1 -sASSERTIONS=0 -sEVAL_CTORS=2"
```

- `-Oz`: Optimize for smallest binary size
- `-flto`: Link-time optimization for dead code elimination
- `--closure=1`: Closure Compiler minification
- `-sASSERTIONS=0`: Remove runtime assertions
- `-sEVAL_CTORS=2`: Evaluate constructors at compile time

## Usage

### Cloudflare Workers

```typescript
import { PGlite } from '@dotdo/pglite'
import pgliteWasm from './pglite-tiny.wasm'
import pgliteData from './pglite-tiny.data'

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const pg = await PGlite.create({
      wasmModule: pgliteWasm,
      fsBundle: new Blob([pgliteData]),
    })

    // Create a simple cache table
    await pg.exec(`
      CREATE TABLE IF NOT EXISTS cache (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        expires_at TIMESTAMP
      )
    `)

    // Insert with parameters
    await pg.query(
      'INSERT INTO cache (key, value, expires_at) VALUES ($1, $2, $3)',
      ['session:abc123', '{"user": "alice"}', new Date(Date.now() + 3600000)]
    )

    // Simple lookup
    const result = await pg.query(
      'SELECT value FROM cache WHERE key = $1 AND expires_at > NOW()',
      ['session:abc123']
    )

    return Response.json(result.rows[0] || null)
  }
}
```

### Browser (Simple Key-Value)

```typescript
import { PGlite } from '@dotdo/pglite'

const pg = await PGlite.create()

// Simple config storage
await pg.exec(`
  CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
`)

// Upsert pattern (INSERT ... ON CONFLICT requires btree unique index)
await pg.exec(`
  INSERT INTO config (key, value) VALUES ('theme', 'dark')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
`)

// Lookup
const result = await pg.query("SELECT value FROM config WHERE key = 'theme'")
console.log(result.rows[0]?.value) // 'dark'
```

### Lookup Table Pattern

```typescript
// Create a lookup table for caching
await pg.exec(`
  CREATE TABLE lookup (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    data TEXT
  )
`)

// Bulk insert
const values = [
  [1, 'item1', 'data1'],
  [2, 'item2', 'data2'],
  [3, 'item3', 'data3'],
]

for (const [id, name, data] of values) {
  await pg.query(
    'INSERT INTO lookup (id, name, data) VALUES ($1, $2, $3)',
    [id, name, data]
  )
}

// Fast lookup by primary key
const item = await pg.query('SELECT * FROM lookup WHERE id = $1', [2])
```

## Memory Budget

For Cloudflare Workers (128MB limit):

```
128 MB (Worker limit)
-  3 MB (WASM binary - tiny)
-  1.5 MB (data bundle)
- 16 MB (shared_buffers - reduced for tiny)
-  4 MB (WAL buffers - minimal)
-  5 MB (PostgreSQL overhead)
= ~98 MB available for queries and results
```

The tiny variant leaves the most headroom for application logic and data.

## Size Comparison

| Build Variant | WASM Size | Data Size | Memory | Use Case |
|--------------|-----------|-----------|--------|----------|
| **pglite-tiny** | **~3MB** | **~1.5MB** | **35-40MB** | **Key-value, caching (this variant)** |
| pglite-minimal | ~5MB | ~2MB | 50-55MB | Core SQL, all types |
| pglite-json | ~4MB | ~2MB | 45-50MB | Document storage |
| pglite-fts | ~7MB | ~3.5MB | 60-65MB | Full-text search |
| pglite-vector | ~5MB | ~2MB | 55-60MB | AI/ML vectors |
| pglite-full | ~8.5MB | ~4.7MB | 80MB | All features |

## When to Use This Variant

**Use pglite-tiny when:**
- Bundle size is critical (< 5MB total)
- Memory is extremely limited
- Only simple key-value or lookup queries needed
- No complex SQL operations required
- Maximum headroom for application code
- Baseline performance benchmarking

**Use another variant when:**
- You need JOINs or complex queries (use pglite-minimal)
- You need JSON document storage (use pglite-json)
- You need full-text search (use pglite-fts)
- You need vector similarity (use pglite-vector)
- You need any extensions (use pglite-full)

## Limitations

### Query Complexity

The tiny variant is optimized for simple queries. Complex queries may:
- Have higher memory overhead due to unoptimized code paths
- Be slower than in larger variants
- Potentially fail for very complex query plans

### No Type Coercion

Without full type support, some implicit type coercions may not work:
- Always use explicit casts when needed
- Stick to basic types (integer, text, boolean, timestamp)

### No JSONB

If you need JSON storage, store it as TEXT and parse in your application:
```typescript
// Store
await pg.query('INSERT INTO data (id, json_text) VALUES ($1, $2)',
  [1, JSON.stringify({ foo: 'bar' })])

// Retrieve and parse
const result = await pg.query('SELECT json_text FROM data WHERE id = $1', [1])
const data = JSON.parse(result.rows[0].json_text)
```

### No Full-Text Search

For text search, use LIKE patterns:
```sql
SELECT * FROM products WHERE name LIKE '%search%'
```

Or implement search in your application layer.

## Testing

```bash
cd packages/pglite/postgres-pglite
npx vitest run tests/tiny-variant.test.ts
```

## Related Issues

- postgres-vgah: pglite: Build and validate tiny variant
- postgres-4box: Build variants epic

## License

Same as PGLite (PostgreSQL License)
