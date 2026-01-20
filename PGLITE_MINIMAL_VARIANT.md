# PGLite Minimal Variant

Core SQL only PGLite build for general-purpose database operations without extensions.

## Overview

The minimal variant (`pglite-minimal`) is a balanced PGLite build that includes full SQL functionality while excluding all extensions. It provides the sweet spot between the tiny variant (too minimal for most uses) and the full variant (too large for edge deployment).

**Target Metrics:**
- WASM size: ~5MB
- Data bundle: ~2MB (LZ4 compressed)
- Total bundle: ~7MB
- Memory usage: ~50-55MB

## Use Cases

- General-purpose SQL queries
- CRUD operations
- Cloudflare Workers deployments (128MB limit)
- Edge computing with minimal footprint
- Local-first applications
- Offline data storage
- Lightweight analytics
- Configuration management
- User preferences storage

## Features Included

### SQL Executor (Full)

**Data Manipulation:**
- SELECT with all clauses (WHERE, GROUP BY, HAVING, ORDER BY, LIMIT, OFFSET)
- INSERT (single row, bulk, ON CONFLICT)
- UPDATE (standard, FROM clause, RETURNING)
- DELETE (standard, USING, RETURNING)
- MERGE (PostgreSQL 15+)
- TRUNCATE

**Joins:**
- INNER JOIN
- LEFT/RIGHT/FULL OUTER JOIN
- CROSS JOIN
- LATERAL joins
- Self joins

**Advanced Queries:**
- Subqueries (scalar, row, table)
- Common Table Expressions (WITH, recursive CTEs)
- Window functions (ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD, etc.)
- Aggregate functions (COUNT, SUM, AVG, MIN, MAX, array_agg, string_agg, etc.)
- Set operations (UNION, INTERSECT, EXCEPT)
- CASE expressions
- COALESCE, NULLIF, GREATEST, LEAST

**Prepared Statements:**
- Parameterized queries ($1, $2, ...)
- PREPARE/EXECUTE/DEALLOCATE
- Server-side prepared statements

### Index Types (All)

| Index Type | Use Case | Operators |
|------------|----------|-----------|
| B-tree | Default, range queries, ordering | <, <=, =, >=, >, BETWEEN |
| Hash | Equality only | = |
| GIN | Arrays, JSONB, full-text | @>, <@, ?, ?&, ?|, @@ |
| GiST | Geometric, range types, FTS | &&, @>, <@, <<, >>, etc. |
| BRIN | Large tables with natural ordering | <, <=, =, >=, > |

### Data Types (All Core Types)

**Numeric:**
- `smallint` (int2) - 2 bytes
- `integer` (int4) - 4 bytes
- `bigint` (int8) - 8 bytes
- `decimal/numeric` - variable precision
- `real` (float4) - 4-byte floating point
- `double precision` (float8) - 8-byte floating point
- `serial`, `bigserial` - auto-incrementing

**Character:**
- `char(n)` - fixed-length
- `varchar(n)` - variable-length with limit
- `text` - unlimited length

**Date/Time:**
- `date` - date only
- `time` - time only (with/without timezone)
- `timestamp` - date and time (with/without timezone)
- `interval` - time span

**Boolean:**
- `boolean` - true/false/null

**Binary:**
- `bytea` - binary data

**UUID:**
- `uuid` - universally unique identifier
- Built-in gen_random_uuid() function

**JSON:**
- `json` - text storage
- `jsonb` - binary storage with indexing
- All JSON operators and functions

**Arrays:**
- Any type as array: `int[]`, `text[]`, `jsonb[]`, etc.
- Array operators and functions

**Range Types:**
- `int4range`, `int8range`, `numrange`
- `daterange`, `tsrange`, `tstzrange`
- Range operators: &&, @>, <@, etc.

**Network Types (Built-in):**
- `inet` - IPv4/IPv6 address
- `cidr` - network specification
- `macaddr`, `macaddr8` - MAC addresses

**Geometric Types (Built-in):**
- `point`, `line`, `lseg`
- `box`, `circle`, `polygon`, `path`

### Transactions (Full ACID)

- BEGIN/START TRANSACTION
- COMMIT/END
- ROLLBACK
- SAVEPOINT/RELEASE SAVEPOINT/ROLLBACK TO SAVEPOINT
- Isolation levels: READ COMMITTED, REPEATABLE READ, SERIALIZABLE
- Row-level locking: FOR UPDATE, FOR SHARE

### Schema Management

**Tables:**
- CREATE TABLE (including IF NOT EXISTS)
- ALTER TABLE (ADD/DROP/ALTER COLUMN, constraints, etc.)
- DROP TABLE
- TRUNCATE TABLE
- Table inheritance
- Partitioning (RANGE, LIST, HASH)

**Constraints:**
- PRIMARY KEY
- FOREIGN KEY (with ON DELETE/UPDATE actions)
- UNIQUE
- CHECK
- NOT NULL
- EXCLUDE (with GiST)

**Other Objects:**
- VIEWs (including materialized views)
- INDEXes (all types)
- SEQUENCEs
- GENERATED columns (STORED)
- DEFAULT values

### Text Search (Basic)

- English Snowball stemmer
- `to_tsvector()`, `to_tsquery()`, `plainto_tsquery()`
- `@@` match operator
- `ts_rank()` for ranking
- GIN indexes for tsvector

## Features Excluded

### Contrib Extensions (All)

The following extensions are NOT included:

| Extension | Description | Alternative |
|-----------|-------------|-------------|
| pgvector | Vector similarity search | Use pglite-vector variant |
| pgcrypto | Cryptographic functions | Use pglite-full variant |
| pg_trgm | Trigram similarity | Use pglite-fts variant |
| fuzzystrmatch | Phonetic matching | Use pglite-fts variant |
| hstore | Key-value store | Use JSONB instead |
| ltree | Hierarchical data | Use recursive CTEs or JSONB |
| intarray | Integer array functions | Use array operators |
| citext | Case-insensitive text | Use LOWER() or collation |
| uuid-ossp | UUID generation | Use gen_random_uuid() |
| earthdistance | Geographic calculations | Implement in application |
| tablefunc | Crosstab queries | Use CASE/FILTER |
| xml2 | XML processing | Use JSONB instead |
| postgis | Geographic objects | Not suitable for edge |

### Language Support

- **Non-English stemmers**: ~500KB savings
  - 26+ languages removed (Arabic, German, French, Spanish, etc.)

- **Non-UTF-8 charset converters**: ~1.8MB savings
  - Asian encodings (Big5, GB18030, EUC-JP, EUC-KR, SJIS)
  - Latin encodings (ISO-8859-*, Windows-125*)
  - Other legacy encodings

### Other Exclusions

- ICU collation (basic collation still works)
- XML/XSLT processing
- Native Language Support (NLS) for error messages

## Building

```bash
cd packages/pglite/postgres-pglite

# Standard minimal build (release mode)
./build-pglite-minimal.sh

# Debug build with symbols
DEBUG=true ./build-pglite-minimal.sh

# Custom memory allocation
TOTAL_MEMORY=128MB ./build-pglite-minimal.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DEBUG` | `false` | Build debug or release version |
| `TOTAL_MEMORY` | `64MB` | Initial memory allocation |
| `CMA_MB` | `8` | Wire query zone size in MB |
| `PGLITE_UTF8_ONLY` | `true` | UTF-8 only charset support |
| `SNOWBALL_LANGUAGES` | `english` | Snowball stemmer languages |
| `SKIP_CONTRIB` | `true` | Skip all contrib extensions |

## Usage

### Cloudflare Workers

```typescript
import { PGlite } from '@dotdo/pglite'
import pgliteWasm from './pglite.wasm'
import pgliteData from './pglite.data'

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const pg = await PGlite.create({
      wasmModule: pgliteWasm,
      fsBundle: new Blob([pgliteData]),
    })

    // Create tables
    await pg.exec(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        name TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `)

    // Insert with parameters
    await pg.query(
      'INSERT INTO users (email, name) VALUES ($1, $2) RETURNING id',
      ['user@example.com', 'John Doe']
    )

    // Query with joins
    const result = await pg.query(`
      SELECT u.name, COUNT(o.id) as order_count
      FROM users u
      LEFT JOIN orders o ON o.user_id = u.id
      GROUP BY u.id, u.name
      ORDER BY order_count DESC
    `)

    return Response.json(result.rows)
  }
}
```

### Browser

```typescript
import { PGlite } from '@dotdo/pglite'

const pg = await PGlite.create()

// Use JSONB for flexible schema
await pg.exec(`
  CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX documents_data_gin ON documents USING GIN (data);
`)

// Insert JSON documents
await pg.query(
  "INSERT INTO documents (data) VALUES ($1)",
  [JSON.stringify({ type: 'article', title: 'Hello World', tags: ['intro'] })]
)

// Query with JSONB operators
const articles = await pg.query(`
  SELECT data->>'title' as title
  FROM documents
  WHERE data @> '{"type": "article"}'
  AND data->'tags' ? 'intro'
`)
```

## Memory Budget

For Cloudflare Workers (128MB limit):

```
128 MB (Worker limit)
-  5 MB (WASM binary)
-  2 MB (data bundle)
-  1 MB (JS runtime)
- 16 MB (shared_buffers default)
- 16 MB (WAL buffers)
- 10 MB (PostgreSQL overhead)
= ~78 MB available for queries and results
```

## Size Comparison

| Build Variant | WASM Size | Data Size | Memory | Use Case |
|--------------|-----------|-----------|--------|----------|
| pglite-tiny | ~3MB | ~1.5MB | 35-40MB | Minimal key-value |
| **pglite-minimal** | **~5MB** | **~2MB** | **50-55MB** | **Core SQL (this variant)** |
| pglite-json | ~4MB | ~2MB | 45-50MB | Document storage |
| pglite-fts | ~7MB | ~3.5MB | 60-65MB | Full-text search |
| pglite-vector | ~5MB | ~2MB | 55-60MB | AI/ML vectors |
| pglite-full | ~8.5MB | ~4.7MB | 80MB | All features |

## When to Use This Variant

**Use pglite-minimal when:**
- You need standard SQL operations (CRUD, joins, transactions)
- No extensions are required
- Deploying to memory-constrained environments
- Bundle size is a concern
- General-purpose database needs

**Use another variant when:**
- You need full-text search with fuzzy matching (use pglite-fts)
- You need vector similarity search (use pglite-vector)
- You need cryptographic functions (use pglite-full)
- You need multi-language text processing (use pglite-full)
- You need maximum compatibility (use pglite-full)

## Testing

```bash
cd packages/pglite/postgres-pglite
npx vitest run tests/minimal-variant.test.ts
```

## Related Issues

- postgres-1dw3: Create pglite-minimal build variant (core SQL only)
- postgres-4box: Build variants epic

## License

Same as PGLite (PostgreSQL License)
