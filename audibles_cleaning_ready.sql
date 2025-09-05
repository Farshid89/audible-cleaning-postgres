-- Audible Dataset Cleaning (PostgreSQL)
-- Minimal fixes & clearer comments; logic stays yours.
-- Run in psql: \i audibles_cleaning_ready.sql

BEGIN;  -- Wrap everything so you can ROLLBACK on error

/* 0) Create a staging copy so the raw table remains untouched */
-- If you already have audibles_staging from a previous run, drop it to avoid conflicts
DROP TABLE IF EXISTS audibles_staging;

-- Original raw table structure
-- CREATE TABLE audibles (
--   name TEXT,
--   author TEXT,
--   narrator TEXT,
--   time TEXT,
--   releasedate TEXT,
--   language TEXT,
--   stars TEXT,
--   price TEXT
-- );

-- Clone the raw data into a staging working table
CREATE TABLE audibles_staging AS TABLE audibles;

/* 1) Rename columns for clarity (matches your original intent) */
ALTER TABLE audibles_staging RENAME COLUMN name        TO book_name;
ALTER TABLE audibles_staging RENAME COLUMN time        TO duration;
ALTER TABLE audibles_staging RENAME COLUMN releasedate TO release_date;

/* 2) Quick duplicate check (read-only sanity check) */

WITH ranked AS (
   SELECT *,
          ROW_NUMBER() OVER (
            PARTITION BY book_name, author, narrator, duration, release_date, language, stars, price
          ) AS rn
   FROM audibles_staging
 )
SELECT * FROM ranked WHERE rn > 1;

/* 3) Clean `author`
   - Remove 'Writtenby:' prefix
   - Insert spaces between camelCase boundaries (e.g., GeronimoStilton -> Geronimo Stilton)*/
UPDATE audibles_staging
SET author = TRIM(
  REGEXP_REPLACE(
    SUBSTRING(author, 11),         -- drop the first 10 chars: 'Writtenby:'
    '([a-z])([A-Z])', '\1 \2', 'g'
  )
);

/* 4) Clean `narrator`
   - Remove 'Narratedby:' prefix
   - Insert spaces between camelCase boundaries*/
UPDATE audibles_staging
SET narrator = TRIM(
  REGEXP_REPLACE(
    SUBSTRING(narrator, 12),       -- drop the first 11 chars: 'Narratedby:'
    '([a-z])([A-Z])', '\1 \2', 'g'
  )
);

/* 5) Normalize `duration` to total minutes (INTEGER)
   Handles examples like:
     '2 hrs and 32 mins', '1 hr and 32 mins', '1 hr', '25 hrs', '10 mins', 'Less than a minute'*/
ALTER TABLE audibles_staging
ALTER COLUMN duration TYPE INTEGER
USING (
  CASE
    WHEN duration = 'Less than a minute' THEN 0
    ELSE
      COALESCE( (regexp_match(duration, '([0-9]+)\s*(hr|hrs)'))[1]::int, 0 ) * 60 +
      COALESCE( (regexp_match(duration, '([0-9]+)\s*(min|mins)'))[1]::int, 0 )
  END
);

/* 6) Standardize `release_date` text -> date */
UPDATE audibles_staging
SET release_date = TO_DATE(release_date, 'DD-MM-YY');

/* 7) Split `stars` text into:
      - numeric star value (e.g., '4.7')
      - number of ratings (e.g., '126')
   Notes:
     - Keep NULL for 'Not rated yet'
     - Regex handles both 'rating' and 'ratings'
*/
ALTER TABLE audibles_staging
  ADD COLUMN IF NOT EXISTS ratings TEXT;

-- Ratings first, while `stars` still contains the original sentence
UPDATE audibles_staging
SET ratings = (regexp_match(stars, '([0-9]+)\s*ratings?'))[1];

-- Now reduce `stars` to just the numeric value before 'out'
UPDATE audibles_staging
SET stars = CASE
  WHEN stars = 'Not rated yet' THEN NULL
  ELSE SUBSTRING(stars, 1, POSITION('out' IN stars) - 2)
END;

/* 8) Clean `price`
   - Remove thousands separators (e.g., '1,299.99' -> '1299.99')
   - Convert 'Free' to 0.00
*/
UPDATE audibles_staging
SET price = REPLACE(price, ',', '')
WHERE price LIKE '%,%';

UPDATE audibles_staging
SET price = '0.00'
WHERE price ILIKE '%Free%';

/* 9) Final types
   Use NULLIF on text->numeric casts to avoid errors on empty strings
*/
ALTER TABLE audibles_staging
  ALTER COLUMN price        TYPE DECIMAL(10,2) USING NULLIF(price,'')::DECIMAL(10,2),
  ALTER COLUMN release_date TYPE DATE          USING release_date::DATE,
  ALTER COLUMN stars        TYPE DECIMAL(2,1)  USING NULLIF(stars,'')::DECIMAL(2,1),
  ALTER COLUMN ratings      TYPE INTEGER       USING NULLIF(ratings,'')::INTEGER;

COMMIT;

/* ---- OPTIONAL: quick sanity checks -----------------
SELECT * FROM audibles_staging LIMIT 20;
SELECT book_name, author, narrator, duration, release_date, stars, ratings, price
FROM audibles_staging
ORDER BY release_date DESC, stars DESC NULLS LAST, ratings DESC NULLS LAST
LIMIT 20;

/*
-- OPTIONAL: Export cleaned data
-- \copy (SELECT * FROM audibles_staging) TO 'audible_cleaned.csv' WITH CSV HEADER
------------------------------------------------------------------ */
