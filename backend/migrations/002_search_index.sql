-- Fast product name search (NFR-07). PostgreSQL only; not applied to the in-memory test database.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX products_name_trgm_idx ON products USING GIN (name gin_trgm_ops);
