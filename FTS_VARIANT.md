# PGLite FTS Variant

Full-Text Search optimized PGLite build for search-focused applications.

## Overview

The FTS variant is a size-optimized PGLite build specifically designed for full-text search use cases. It includes all essential FTS functionality while excluding features not needed for search workloads.

**Target Metrics:**
- Bundle size: ~10.5MB (WASM ~7MB + data ~3.5MB)
- Memory usage: ~60-65MB

## Use Cases

- Search engines
- Content management systems
- Documentation search
- Product catalogs
- Knowledge bases
- Blog/article search

## Features Included

### Core Full-Text Search
- **tsvector/tsquery types** - Vector representation of documents and queries
- **English Snowball stemmer** - Word normalization (running -> run)
- **Stop words filtering** - Common words removed from index
- **GIN indexes** - Fast full-text search queries
- **Ranking functions** - ts_rank, ts_rank_cd
- **Highlighting** - ts_headline for search results

### pg_trgm Extension
- **Trigram similarity** - similarity(), word_similarity()
- **Fuzzy matching** - % and <-> operators
- **GIN/GiST indexes** - gin_trgm_ops, gist_trgm_ops
- **Typo tolerance** - Find matches despite spelling errors

### fuzzystrmatch Extension
- **soundex** - Phonetic algorithm for name matching
- **levenshtein** - Edit distance calculation
- **metaphone** - Phonetic encoding
- **dmetaphone** - Double metaphone for better accuracy

### Other Features
- JSON/JSONB support
- Basic PostgreSQL functionality
- UTF-8 character support

## Features Excluded (for size optimization)

- Non-English Snowball stemmers (~500KB savings)
- Non-UTF-8 charset converters (~1.8MB savings)
- ICU internationalization library
- Replication features
- Advanced geometric types
- Network address types

## Building

```bash
cd packages/pglite/postgres-pglite

# Build with defaults (release mode)
./build-pglite-fts.sh

# Build debug version
DEBUG=true ./build-pglite-fts.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| DEBUG | false | Build debug or release |
| CMA_MB | 8 | Memory zone size in MB |
| TOTAL_MEMORY | 64MB | Total memory allocation |

## Usage

```typescript
import { PGlite } from '@dotdo/pglite-fts'

const db = await PGlite.create()

// Create a searchable table
await db.exec(`
  CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    title TEXT,
    content TEXT,
    search_vector tsvector GENERATED ALWAYS AS (
      setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
      setweight(to_tsvector('english', coalesce(content, '')), 'B')
    ) STORED
  );

  CREATE INDEX documents_search_idx ON documents USING GIN (search_vector);
`)

// Insert documents
await db.exec(`
  INSERT INTO documents (title, content) VALUES
  ('PostgreSQL Guide', 'Learn PostgreSQL database administration'),
  ('MySQL Tutorial', 'Getting started with MySQL databases');
`)

// Full-text search
const results = await db.query(`
  SELECT title, ts_rank(search_vector, query) as rank
  FROM documents, to_tsquery('english', 'postgresql') query
  WHERE search_vector @@ query
  ORDER BY rank DESC
`)
```

## Full-Text Search Examples

### Basic FTS

```sql
-- Create tsvector from text
SELECT to_tsvector('english', 'The quick brown fox jumps');
-- Result: 'brown':3 'fox':4 'jump':5 'quick':2

-- Create tsquery
SELECT to_tsquery('english', 'quick & fox');
-- Result: 'quick' & 'fox'

-- Match query against document
SELECT to_tsvector('english', 'The quick brown fox') @@
       to_tsquery('english', 'quick & fox');
-- Result: true
```

### Search Ranking

```sql
-- Rank search results
SELECT title,
       ts_rank(search_vector, to_tsquery('english', 'database')) as rank
FROM documents
WHERE search_vector @@ to_tsquery('english', 'database')
ORDER BY rank DESC;

-- Highlight matches
SELECT ts_headline(
  'english',
  content,
  to_tsquery('english', 'database'),
  'StartSel=<mark>, StopSel=</mark>'
) as highlighted
FROM documents
WHERE search_vector @@ to_tsquery('english', 'database');
```

### Weighted Search

```sql
-- Different weights for title vs content
SELECT title,
       ts_rank(
         setweight(to_tsvector('english', title), 'A') ||
         setweight(to_tsvector('english', content), 'B'),
         to_tsquery('english', 'guide')
       ) as rank
FROM documents
ORDER BY rank DESC;
```

## pg_trgm Examples

```sql
-- Load extension
CREATE EXTENSION pg_trgm;

-- Similarity score (0-1)
SELECT similarity('PostgreSQL', 'Postgre');
-- Result: 0.5

-- Find similar strings
SELECT name FROM products
WHERE name % 'Postgresql'  -- % operator for similarity match
ORDER BY name <-> 'Postgresql';  -- <-> operator for distance

-- Create GIN index for fast fuzzy search
CREATE INDEX products_name_trgm ON products USING GIN (name gin_trgm_ops);
```

## fuzzystrmatch Examples

```sql
-- Load extension
CREATE EXTENSION fuzzystrmatch;

-- Soundex for phonetic matching
SELECT soundex('Robert'), soundex('Rupert');
-- Both return similar codes

-- Levenshtein edit distance
SELECT levenshtein('kitten', 'sitting');
-- Result: 3 (3 edits needed)

-- Metaphone for phonetic encoding
SELECT metaphone('phone', 10), metaphone('fone', 10);
-- Both return same code
```

## Performance Tips

1. **Use generated tsvector columns** - Avoid computing tsvector on every query
2. **Create GIN indexes** - Essential for fast FTS queries
3. **Use plainto_tsquery for user input** - Safer than to_tsquery
4. **Combine FTS with trigrams** - Use FTS for relevance, trigrams for typo tolerance
5. **Limit result sets** - Use LIMIT with ORDER BY rank

## Size Comparison

| Build Variant | WASM Size | Data Size | Total Bundle | Memory |
|--------------|-----------|-----------|--------------|--------|
| Full | ~8.5MB | ~4.7MB | ~13.2MB | 128MB |
| FTS | ~7MB | ~3.5MB | ~10.5MB | 64MB |
| Minimal | ~4MB | ~1.5MB | ~5.5MB | 32MB |

## Testing

Run the FTS variant tests:

```bash
cd packages/pglite/postgres-pglite
npx vitest run tests/fts-variant.test.ts
```

## Related Issues

- postgres-4box: PGLite Build Variants (Epic)
- postgres-4box.4: Create pglite-fts build variant
