-- Shared platform schema (../tasks.md SH-10) used by all three modules.
-- Money is stored in paise (integer). Timestamps are written by the application clock.

CREATE TABLE schema_migrations (
  name        TEXT PRIMARY KEY,
  applied_at  TIMESTAMPTZ NOT NULL
);

CREATE TABLE stores (
  id         UUID PRIMARY KEY,
  code       TEXT NOT NULL UNIQUE,
  name       TEXT NOT NULL,
  address    TEXT,
  lat        DOUBLE PRECISION NOT NULL,
  lng        DOUBLE PRECISION NOT NULL,
  is_active  BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE store_managers (
  id         UUID PRIMARY KEY,
  store_id   UUID NOT NULL UNIQUE REFERENCES stores(id),
  name       TEXT NOT NULL,
  mobile     TEXT NOT NULL UNIQUE,
  is_active  BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE delivery_boys (
  id         UUID PRIMARY KEY,
  store_id   UUID NOT NULL REFERENCES stores(id),
  code       TEXT NOT NULL UNIQUE,
  name       TEXT NOT NULL,
  mobile     TEXT NOT NULL UNIQUE,
  is_active  BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE users (
  id             UUID PRIMARY KEY,
  mobile         TEXT NOT NULL UNIQUE,
  created_at     TIMESTAMPTZ NOT NULL,
  last_login_at  TIMESTAMPTZ
);

CREATE TABLE otp_requests (
  id           UUID PRIMARY KEY,
  mobile       TEXT NOT NULL,
  role         TEXT NOT NULL,
  otp_hash     TEXT NOT NULL,
  status       TEXT NOT NULL,            -- ACTIVE | USED | REPLACED
  attempts     INTEGER NOT NULL DEFAULT 0,
  expires_at   TIMESTAMPTZ NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL
);
CREATE INDEX otp_requests_mobile_role_idx ON otp_requests (mobile, role, created_at);

CREATE TABLE sessions (
  id            UUID PRIMARY KEY,
  subject_id    UUID NOT NULL,           -- users.id, store_managers.id or delivery_boys.id
  role          TEXT NOT NULL,
  store_id      UUID,
  created_at    TIMESTAMPTZ NOT NULL,
  last_used_at  TIMESTAMPTZ NOT NULL,
  revoked_at    TIMESTAMPTZ
);

CREATE TABLE products (
  id          UUID PRIMARY KEY,
  name        TEXT NOT NULL,
  unit        TEXT NOT NULL,
  price_paise INTEGER NOT NULL CHECK (price_paise > 0),
  image_url   TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE checkouts (
  id               UUID PRIMARY KEY,
  user_id          UUID NOT NULL REFERENCES users(id),
  store_id         UUID NOT NULL REFERENCES stores(id),
  address          JSONB NOT NULL,
  lat              DOUBLE PRECISION NOT NULL,
  lng              DOUBLE PRECISION NOT NULL,
  road_distance_m  INTEGER NOT NULL,
  items            JSONB NOT NULL,       -- server-priced lines
  total_paise      INTEGER NOT NULL,
  status           TEXT NOT NULL,        -- OPEN | PAID | EXPIRED
  expires_at       TIMESTAMPTZ NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL
);
CREATE INDEX checkouts_user_idx ON checkouts (user_id, created_at);

CREATE TABLE payments (
  id                  UUID PRIMARY KEY,
  checkout_id         UUID NOT NULL REFERENCES checkouts(id),
  gateway_order_id    TEXT NOT NULL UNIQUE,
  gateway_payment_id  TEXT UNIQUE,
  amount_paise        INTEGER NOT NULL,
  status              TEXT NOT NULL,     -- CREATED | CAPTURED | FAILED | CAPTURED_ORPHAN
  window_ends_at      TIMESTAMPTZ NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL,
  updated_at          TIMESTAMPTZ NOT NULL
);

CREATE TABLE orders (
  id                UUID PRIMARY KEY,
  display_id        TEXT NOT NULL UNIQUE,
  user_id           UUID NOT NULL REFERENCES users(id),
  store_id          UUID NOT NULL REFERENCES stores(id),
  checkout_id       UUID NOT NULL UNIQUE REFERENCES checkouts(id),
  payment_id        UUID NOT NULL REFERENCES payments(id),
  delivery_address  JSONB NOT NULL,
  total_paise       INTEGER NOT NULL,
  status            TEXT NOT NULL,       -- PLACED | OUT_FOR_DELIVERY | DELIVERED | UNDELIVERED
  delivery_boy_id   UUID REFERENCES delivery_boys(id),
  placed_at         TIMESTAMPTZ NOT NULL,
  assigned_at       TIMESTAMPTZ,
  closed_at         TIMESTAMPTZ,
  undelivered_reason TEXT,
  version           INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX orders_user_idx ON orders (user_id, placed_at);
CREATE INDEX orders_store_status_idx ON orders (store_id, status, placed_at);
CREATE INDEX orders_delivery_boy_idx ON orders (delivery_boy_id, status);

CREATE TABLE order_items (
  id                UUID PRIMARY KEY,
  order_id          UUID NOT NULL REFERENCES orders(id),
  product_id        UUID NOT NULL REFERENCES products(id),
  name_snapshot     TEXT NOT NULL,
  unit_snapshot     TEXT NOT NULL,
  unit_price_paise  INTEGER NOT NULL,
  qty               INTEGER NOT NULL,
  line_total_paise  INTEGER NOT NULL
);

CREATE TABLE order_status_history (
  id           UUID PRIMARY KEY,
  order_id     UUID NOT NULL REFERENCES orders(id),
  from_status  TEXT,
  to_status    TEXT NOT NULL,
  actor_role   TEXT NOT NULL,            -- SYSTEM | STORE_MANAGER | DELIVERY_BOY
  actor_id     UUID,
  reason       TEXT,
  at           TIMESTAMPTZ NOT NULL
);
CREATE INDEX order_status_history_order_idx ON order_status_history (order_id, at);
