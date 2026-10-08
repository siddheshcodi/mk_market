-- Delivery OTPs (Delivery Boy spec §7). OTPs are stored only as an HMAC (NFR-02).
CREATE TABLE delivery_otps (
  id          UUID PRIMARY KEY,
  order_id    UUID NOT NULL REFERENCES orders(id),
  otp_hash    TEXT NOT NULL,
  status      TEXT NOT NULL,             -- ACTIVE | USED | REPLACED | EXHAUSTED (expiry is worked out from expires_at)
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX delivery_otps_order_idx ON delivery_otps (order_id, created_at);
-- BR-19: one valid OTP per order at a time.
CREATE UNIQUE INDEX delivery_otps_one_active ON delivery_otps (order_id) WHERE status = 'ACTIVE';

-- Attempts and resends are counted per order, not per OTP (spec OI-D1).
-- Every send, resend and verify locks this row, so parallel requests can't go over the limits.
CREATE TABLE delivery_otp_counters (
  order_id       UUID PRIMARY KEY REFERENCES orders(id),
  attempts_used  INTEGER NOT NULL DEFAULT 0,
  resends_used   INTEGER NOT NULL DEFAULT 0,
  last_sent_at   TIMESTAMPTZ NOT NULL
);
