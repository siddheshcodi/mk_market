-- Saved results of actions sent with an Idempotency-Key header (../tasks.md SH-21, NFR-11).
-- A retry with the same key gets the saved result instead of acting twice.
CREATE TABLE idempotency_keys (
  actor_id    UUID NOT NULL,
  endpoint    TEXT NOT NULL,
  key         TEXT NOT NULL,
  response    JSONB NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (actor_id, endpoint, key)
);
CREATE INDEX idempotency_keys_created_idx ON idempotency_keys (created_at);

-- The number a session logged in with. Staff sessions end when that number is no longer
-- in config/staff.yaml for this person (A15).
ALTER TABLE sessions ADD COLUMN mobile TEXT;
