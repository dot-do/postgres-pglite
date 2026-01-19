/**
 * PGLite FTS Variant Tests
 *
 * Tests specifically for the Full-Text Search optimized PGLite variant.
 * These tests verify that the FTS variant includes all expected functionality:
 *
 * 1. English Full-Text Search
 *    - tsvector and tsquery types
 *    - English Snowball stemmer
 *    - Stop words filtering
 *
 * 2. GIN Index Support
 *    - GIN index creation on tsvector columns
 *    - GIN index on expressions
 *
 * 3. pg_trgm Extension
 *    - Trigram similarity matching
 *    - GIN/GiST indexes with trigrams
 *
 * 4. fuzzystrmatch Extension
 *    - soundex function
 *    - levenshtein distance
 *    - metaphone function
 *    - dmetaphone (double metaphone)
 *
 * Target metrics for FTS variant:
 *   - Bundle size: ~6MB
 *   - Memory usage: ~60-65MB
 */

import { describe, it, expect, afterEach, beforeAll } from 'vitest'
import { PGlite } from '../../packages/pglite/dist/index.js'

// Extensions - these will be bundled in the FTS variant
// For testing, we load them dynamically if available
let pg_trgm: unknown
let fuzzystrmatch: unknown

describe('PGLite FTS Variant', () => {
  let instances: PGlite[] = []

  beforeAll(async () => {
    // Try to load extensions dynamically for testing
    try {
      const trgmModule = await import('../../packages/pglite/dist/contrib/pg_trgm.js')
      pg_trgm = trgmModule.pg_trgm
    } catch {
      console.log('pg_trgm extension not available for testing')
    }

    try {
      const fuzzyModule = await import('../../packages/pglite/dist/contrib/fuzzystrmatch.js')
      fuzzystrmatch = fuzzyModule.fuzzystrmatch
    } catch {
      console.log('fuzzystrmatch extension not available for testing')
    }
  })

  afterEach(async () => {
    for (const instance of instances) {
      try {
        if (!instance.closed) {
          await instance.close()
        }
      } catch {
        // Ignore cleanup errors
      }
    }
    instances = []
  })

  function trackInstance(db: PGlite): PGlite {
    instances.push(db)
    return db
  }

  // ===========================================================================
  // 1. English Full-Text Search
  // ===========================================================================

  describe('English Full-Text Search', () => {
    /**
     * Test: English tsvector creation with stemming
     *
     * The English stemmer should normalize words to their root form.
     */
    it('should create tsvector with English stemming', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      const result = await db.query<{ ts: string }>(`
        SELECT to_tsvector('english', 'The running dogs are quickly jumping over fences') as ts
      `)

      expect(result.rows).toHaveLength(1)
      const tsvector = result.rows[0].ts

      // Check stemmed forms
      expect(tsvector).toContain('run') // running -> run
      expect(tsvector).toContain('dog') // dogs -> dog
      expect(tsvector).toContain('quick') // quickly -> quick
      expect(tsvector).toContain('jump') // jumping -> jump
      expect(tsvector).toContain('fenc') // fences -> fenc

      // Stop words should be removed
      expect(tsvector).not.toContain("'the'")
      expect(tsvector).not.toContain("'are'")
      expect(tsvector).not.toContain("'over'")
    })

    /**
     * Test: English tsquery creation
     *
     * The English configuration should properly parse and stem queries.
     */
    it('should create tsquery with English stemming', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      const result = await db.query<{ tq: string }>(`
        SELECT to_tsquery('english', 'running & jumping') as tq
      `)

      expect(result.rows).toHaveLength(1)
      const tsquery = result.rows[0].tq

      // Words should be stemmed in the query too
      expect(tsquery).toContain('run')
      expect(tsquery).toContain('jump')
    })

    /**
     * Test: FTS matching with English configuration
     *
     * Matching should work regardless of word form.
     */
    it('should match stemmed forms in FTS queries', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      // "ran" should match "running" after stemming
      const result = await db.query<{ match: boolean }>(`
        SELECT to_tsvector('english', 'The dog is running fast') @@
               to_tsquery('english', 'ran') as match
      `)

      expect(result.rows[0].match).toBe(true)
    })

    /**
     * Test: English stop words are filtered
     *
     * Common English words should be excluded from the tsvector.
     */
    it('should filter English stop words', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      const result = await db.query<{ ts: string }>(`
        SELECT to_tsvector('english', 'the a an and or but in on at to') as ts
      `)

      // All stop words should result in empty tsvector
      expect(result.rows[0].ts).toBe('')
    })

    /**
     * Test: Simple configuration (no stemming)
     *
     * The 'simple' configuration should be available for non-stemmed search.
     */
    it('should support simple configuration without stemming', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      const english = await db.query<{ ts: string }>(`
        SELECT to_tsvector('english', 'running') as ts
      `)
      expect(english.rows[0].ts).toContain('run')

      const simple = await db.query<{ ts: string }>(`
        SELECT to_tsvector('simple', 'running') as ts
      `)
      expect(simple.rows[0].ts).toContain('running')
    })

    /**
     * Test: English-only build verification
     *
     * In an English-only build, other language configs should error.
     * This test only runs when PGLITE_VARIANT=fts is set, since the full build
     * includes all language stemmers and would correctly support French.
     */
    it.skipIf(process.env.PGLITE_VARIANT !== 'fts')('should only have English stemmer in FTS variant', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      // This should work
      await expect(db.query(`
        SELECT to_tsvector('english', 'test')
      `)).resolves.toBeDefined()

      // This should error in English-only build
      await expect(db.query(`
        SELECT to_tsvector('french', 'test')
      `)).rejects.toThrow()
    })
  })

  // ===========================================================================
  // 2. GIN Index Support for FTS
  // ===========================================================================

  describe('GIN Index Support', () => {
    /**
     * Test: Create GIN index on tsvector column
     */
    it('should create GIN index on tsvector column', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      await db.exec(`
        CREATE TABLE documents (
          id SERIAL PRIMARY KEY,
          content TEXT,
          search_vector tsvector GENERATED ALWAYS AS (
            to_tsvector('english', coalesce(content, ''))
          ) STORED
        );
      `)

      await db.exec(`
        CREATE INDEX documents_search_idx ON documents USING GIN (search_vector);
      `)

      const result = await db.query<{ indexname: string; indexdef: string }>(`
        SELECT indexname, indexdef FROM pg_indexes
        WHERE tablename = 'documents' AND indexname = 'documents_search_idx'
      `)

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].indexdef).toContain('gin')
      expect(result.rows[0].indexdef).toContain('search_vector')
    })

    /**
     * Test: GIN index on tsvector expression
     */
    it('should create GIN index on tsvector expression', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      await db.exec(`
        CREATE TABLE articles (
          id SERIAL PRIMARY KEY,
          title TEXT,
          body TEXT
        );
      `)

      await db.exec(`
        CREATE INDEX articles_fts_idx ON articles
        USING GIN ((
          setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(body, '')), 'B')
        ));
      `)

      const result = await db.query<{ indexname: string }>(`
        SELECT indexname FROM pg_indexes
        WHERE tablename = 'articles' AND indexname = 'articles_fts_idx'
      `)

      expect(result.rows).toHaveLength(1)
    })

    /**
     * Test: FTS query uses GIN index
     */
    it('should perform FTS queries with GIN index', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      await db.exec(`
        CREATE TABLE indexed_docs (
          id SERIAL PRIMARY KEY,
          content TEXT,
          tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
        );
        CREATE INDEX idx_docs_tsv ON indexed_docs USING GIN (tsv);
      `)

      // Insert test data
      await db.exec(`
        INSERT INTO indexed_docs (content) VALUES
        ('PostgreSQL full-text search guide'),
        ('MySQL database tutorial'),
        ('MongoDB document storage');
      `)

      const result = await db.query<{ content: string }>(`
        SELECT content FROM indexed_docs
        WHERE tsv @@ to_tsquery('english', 'postgresql')
      `)

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].content).toBe('PostgreSQL full-text search guide')
    })
  })

  // ===========================================================================
  // 3. pg_trgm Extension Tests
  // ===========================================================================

  describe('pg_trgm Extension', () => {
    /**
     * Test: pg_trgm similarity function
     */
    it('should compute trigram similarity', async () => {
      if (!pg_trgm) {
        console.log('Skipping: pg_trgm not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { pg_trgm }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS pg_trgm;')

      const result = await db.query<{ sim: number }>(`
        SELECT similarity('word', 'words') as sim
      `)

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].sim).toBeGreaterThan(0.5)
      expect(result.rows[0].sim).toBeLessThan(1)
    })

    /**
     * Test: pg_trgm distance operator
     */
    it('should compute trigram distance', async () => {
      if (!pg_trgm) {
        console.log('Skipping: pg_trgm not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { pg_trgm }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS pg_trgm;')

      const result = await db.query<{ dist: number }>(`
        SELECT 'word' <-> 'words' as dist
      `)

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].dist).toBeGreaterThan(0)
      expect(result.rows[0].dist).toBeLessThan(1)
    })

    /**
     * Test: pg_trgm similarity operator (%)
     */
    it('should use similarity operator for matching', async () => {
      if (!pg_trgm) {
        console.log('Skipping: pg_trgm not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { pg_trgm }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS pg_trgm;')

      await db.exec(`
        CREATE TABLE products (
          id SERIAL PRIMARY KEY,
          name TEXT
        );
        INSERT INTO products (name) VALUES
        ('PostgreSQL'),
        ('Postgres'),
        ('MySQL'),
        ('MariaDB');
      `)

      const result = await db.query<{ name: string }>(`
        SELECT name FROM products
        WHERE name % 'Postgresql'
        ORDER BY name
      `)

      expect(result.rows.length).toBeGreaterThanOrEqual(1)
      expect(result.rows.some(r => r.name === 'PostgreSQL')).toBe(true)
    })

    /**
     * Test: pg_trgm GIN index
     */
    it('should create GIN index with gin_trgm_ops', async () => {
      if (!pg_trgm) {
        console.log('Skipping: pg_trgm not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { pg_trgm }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS pg_trgm;')

      await db.exec(`
        CREATE TABLE fuzzy_search (
          id SERIAL PRIMARY KEY,
          name TEXT
        );
        CREATE INDEX fuzzy_search_trgm_idx ON fuzzy_search USING GIN (name gin_trgm_ops);
      `)

      const result = await db.query<{ indexname: string }>(`
        SELECT indexname FROM pg_indexes
        WHERE indexname = 'fuzzy_search_trgm_idx'
      `)

      expect(result.rows).toHaveLength(1)
    })

    /**
     * Test: pg_trgm word_similarity
     */
    it('should compute word similarity', async () => {
      if (!pg_trgm) {
        console.log('Skipping: pg_trgm not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { pg_trgm }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS pg_trgm;')

      const result = await db.query<{ ws: number }>(`
        SELECT word_similarity('PostgreSQL', 'PostgreSQL database') as ws
      `)

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].ws).toBe(1) // Exact word match
    })
  })

  // ===========================================================================
  // 4. fuzzystrmatch Extension Tests
  // ===========================================================================

  describe('fuzzystrmatch Extension', () => {
    /**
     * Test: soundex function
     */
    it('should compute soundex codes', async () => {
      if (!fuzzystrmatch) {
        console.log('Skipping: fuzzystrmatch not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { fuzzystrmatch }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;')

      const result = await db.query<{ s1: string; s2: string; s3: string }>(`
        SELECT
          soundex('Robert') as s1,
          soundex('Rupert') as s2,
          soundex('Smith') as s3
      `)

      expect(result.rows).toHaveLength(1)
      // Robert and Rupert should have similar soundex codes
      expect(result.rows[0].s1.substring(0, 2)).toBe(result.rows[0].s2.substring(0, 2))
      // Smith should be different
      expect(result.rows[0].s3).not.toBe(result.rows[0].s1)
    })

    /**
     * Test: levenshtein distance
     */
    it('should compute levenshtein distance', async () => {
      if (!fuzzystrmatch) {
        console.log('Skipping: fuzzystrmatch not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { fuzzystrmatch }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;')

      const result = await db.query<{ d1: number; d2: number; d3: number }>(`
        SELECT
          levenshtein('kitten', 'sitting') as d1,
          levenshtein('hello', 'hello') as d2,
          levenshtein('abc', 'xyz') as d3
      `)

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].d1).toBe(3) // kitten -> sitting = 3 edits
      expect(result.rows[0].d2).toBe(0) // identical = 0 edits
      expect(result.rows[0].d3).toBe(3) // completely different = 3 edits
    })

    /**
     * Test: levenshtein_less_equal for performance
     */
    it('should use levenshtein_less_equal for threshold matching', async () => {
      if (!fuzzystrmatch) {
        console.log('Skipping: fuzzystrmatch not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { fuzzystrmatch }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;')

      const result = await db.query<{ d: number }>(`
        SELECT levenshtein_less_equal('extensive', 'exhaustive', 4) as d
      `)

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].d).toBeLessThanOrEqual(4)
    })

    /**
     * Test: metaphone function
     */
    it('should compute metaphone codes', async () => {
      if (!fuzzystrmatch) {
        console.log('Skipping: fuzzystrmatch not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { fuzzystrmatch }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;')

      const result = await db.query<{ m1: string; m2: string }>(`
        SELECT
          metaphone('phone', 10) as m1,
          metaphone('fone', 10) as m2
      `)

      expect(result.rows).toHaveLength(1)
      // phone and fone should have same metaphone code
      expect(result.rows[0].m1).toBe(result.rows[0].m2)
    })

    /**
     * Test: dmetaphone (double metaphone)
     */
    it('should compute double metaphone codes', async () => {
      if (!fuzzystrmatch) {
        console.log('Skipping: fuzzystrmatch not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { fuzzystrmatch }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;')

      const result = await db.query<{ primary: string; alt: string }>(`
        SELECT
          dmetaphone('Smith') as primary,
          dmetaphone_alt('Smith') as alt
      `)

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].primary).toBeTruthy()
      // Alt might be same or different
    })
  })

  // ===========================================================================
  // 5. Combined FTS Use Cases
  // ===========================================================================

  describe('Combined FTS Use Cases', () => {
    /**
     * Test: Search engine with multiple strategies
     *
     * Real-world search often combines FTS with fuzzy matching.
     */
    it('should implement multi-strategy search', async () => {
      if (!pg_trgm) {
        console.log('Skipping: pg_trgm not available')
        return
      }

      const db = trackInstance(new PGlite({
        extensions: { pg_trgm }
      }))
      await db.waitReady

      await db.exec('CREATE EXTENSION IF NOT EXISTS pg_trgm;')

      // Create a product catalog
      await db.exec(`
        CREATE TABLE catalog (
          id SERIAL PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          search_vector tsvector GENERATED ALWAYS AS (
            setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
            setweight(to_tsvector('english', coalesce(description, '')), 'B')
          ) STORED
        );

        CREATE INDEX catalog_fts_idx ON catalog USING GIN (search_vector);
        CREATE INDEX catalog_name_trgm_idx ON catalog USING GIN (name gin_trgm_ops);
      `)

      await db.exec(`
        INSERT INTO catalog (name, description) VALUES
        ('PostgreSQL Database', 'Advanced open source relational database'),
        ('MySQL Server', 'Popular relational database management system'),
        ('MongoDB Atlas', 'Document-oriented NoSQL database platform'),
        ('Redis Cache', 'In-memory data structure store for caching');
      `)

      // Strategy 1: Full-text search
      const ftsResult = await db.query<{ name: string; rank: number }>(`
        SELECT name, ts_rank(search_vector, query) as rank
        FROM catalog, to_tsquery('english', 'database') query
        WHERE search_vector @@ query
        ORDER BY rank DESC
      `)

      expect(ftsResult.rows.length).toBeGreaterThanOrEqual(2)

      // Strategy 2: Fuzzy matching for typos
      const fuzzyResult = await db.query<{ name: string; dist: number }>(`
        SELECT name, name <-> 'Postgre' as dist
        FROM catalog
        WHERE name % 'Postgre'
        ORDER BY dist
      `)

      expect(fuzzyResult.rows.length).toBeGreaterThanOrEqual(1)
      expect(fuzzyResult.rows[0].name).toBe('PostgreSQL Database')
    })

    /**
     * Test: Document search with highlighting
     */
    it('should highlight search matches', async () => {
      const db = trackInstance(new PGlite())
      await db.waitReady

      const result = await db.query<{ headline: string }>(`
        SELECT ts_headline(
          'english',
          'PostgreSQL is a powerful, open source object-relational database system.',
          to_tsquery('english', 'powerful & database'),
          'StartSel=<mark>, StopSel=</mark>, MaxFragments=1, MaxWords=15'
        ) as headline
      `)

      expect(result.rows).toHaveLength(1)
      expect(result.rows[0].headline).toContain('<mark>')
      expect(result.rows[0].headline).toContain('</mark>')
    })
  })
})
