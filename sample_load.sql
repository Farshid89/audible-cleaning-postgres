-- sample_load.sql : quick start to test with small samples
-- 1) Create raw table
\i schema.sql

-- 2) Load sample CSV (adjust absolute path if needed)
\copy audibles FROM 'data/audible_uncleaned_sample.csv' WITH CSV HEADER

-- 3) Run the cleaning pipeline (creates audibles_staging)
\i audibles_cleaning_ready.sql

-- 4) Inspect results
SELECT book_name, author, narrator, duration, release_date, stars, ratings, price
FROM audibles_staging
LIMIT 20;
