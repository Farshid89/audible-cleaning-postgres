-- schema.sql : raw table for importing text-first CSV
CREATE TABLE IF NOT EXISTS audibles (
  name TEXT,
  author TEXT,
  narrator TEXT,
  time TEXT,
  releasedate TEXT,
  language TEXT,
  stars TEXT,
  price TEXT
);
