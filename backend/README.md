# MK Market – Backend

NestJS + PostgreSQL backend shared by the three app modules. This first version has the shared platform
(login OTP, sessions, staff list, order status rules) and the APIs for all three modules: **User**
(customer), **Store** (store manager) and **Delivery Boy**. Design: `spec.md` and `plan.md` in each module
folder. Work items: `../tasks.md` and `tasks.md` in each module folder.

## Run locally

Needs Node 20+ and PostgreSQL 14+.

```bash
npm install
cp .env.example .env                                   # then fill in values; see comments in the file
cp config/staff.example.yaml config/staff.yaml         # real stores and staff numbers from the client
cp config/products.example.yaml config/products.yaml   # dev only; production products come from the client (A2)
npm run build
npm run migrate                                        # creates tables
npm run seed                                           # loads staff.yaml (and products.yaml if present)
npm start                                              # http://localhost:3000/api/v1
```

`npm run migrate` / `npm run seed` read `DATABASE_URL` from the environment (export it or use a tool such as `dotenv`).

For local development without accounts, `SMS_PROVIDER=console` prints OTPs to the server log and
`MAPS_PROVIDER=dev` estimates road distance from the map pin. Both are refused when `NODE_ENV=production`.
Razorpay test-mode keys are free; turn on auto-capture in the Razorpay dashboard and point its webhook at
`/api/v1/webhooks/payment` (events `payment.captured`, `payment.failed`).

## Tests

```bash
npm test
```

The tests run the real HTTP API against an in-memory PostgreSQL (pg-mem) with fake SMS, maps and payment
gateway. Test names start with the case ID from the module's `testcases.md` where one exists.
pg-mem does not roll back transactions, does not really lock rows, and returns a row from
`INSERT ... ON CONFLICT DO NOTHING RETURNING` even when nothing was inserted. The code does not rely on any of
these, but rollback and parallel-request behaviour still needs a run against real PostgreSQL.

## Customer API (`/api/v1`)

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/auth/otp/request` | Send login OTP (`role`: `USER`, `STORE_MANAGER`, `DELIVERY_BOY`) |
| POST | `/auth/otp/verify` | Log in, returns access + refresh tokens |
| POST | `/auth/token/refresh` | New tokens (session ends after 30 days unused for customers, 12 h for staff) |
| POST | `/auth/logout` | End the session |
| GET | `/products/search?q=` | Search products by name |
| POST | `/checkout` | Check items and address, find the nearest store within 4 km by road, lock price and store |
| GET | `/checkout/:id` | `OPEN`, `PAID` (with order ID), `EXPIRED` or `REFUND_PENDING` |
| POST | `/checkout/:id/payment` | Create the Razorpay order |
| POST | `/checkout/:id/payment/confirm` | App reports payment; creates the order |
| POST | `/webhooks/payment` | Razorpay webhook; creates the order if the app never reported back |
| GET | `/orders`, `/orders/:id` | My orders and order details. No cancel endpoint (FR-U-14) |

## Store manager API (`/api/v1/store`)

The store always comes from the login token, never from the request.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/orders?status=PLACED&since=` | One tab: `PLACED` (New, oldest first), `OUT_FOR_DELIVERY`, `UNDELIVERED` (Returned), `DELIVERED` (last 7 days). `since` lets the New tab poll for new orders only |
| GET | `/orders/:id` | Items, customer name and mobile, address, order placed time, delivery boy, timeline |
| GET | `/delivery-boys` | Active delivery boys of this store with their current order count |
| POST | `/orders/:id/dispatch` | Body `{ deliveryBoyId }`, header `Idempotency-Key`. Assigns and sets "On the way for delivery" in one step |

There is no reject, cancel or status-change endpoint (FR-S-06). Dispatch returns `409 ORDER_STATE_CHANGED`
with the current status when someone else changed the order first; a retry with the same `Idempotency-Key`
returns the original result.

## Delivery boy API (`/api/v1/delivery/orders`)

The delivery boy always comes from the login token; other delivery boys' orders return 404.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `?tab=ACTIVE` / `?tab=COMPLETED` | On the way (oldest assignment first) or delivered/undelivered in the last 7 days |
| GET | `/:id` | Customer name, mobile, full address and map pin while on the way; only area and pincode after it closes (NFR-04) |
| POST | `/:id/delivery-otp` | "Delivered" tap: sends a 4-digit OTP by SMS to the customer's registered number. A second tap sends nothing |
| POST | `/:id/delivery-otp/resend` | New OTP, old one stops working. Up to 2 per order, 30 seconds apart |
| POST | `/:id/delivery-otp/verify` | Body `{ otp }`, header `Idempotency-Key`. Correct: `DELIVERED`. Wrong: `400 OTP_INCORRECT` with `attemptsLeft`. 3rd wrong: `UNDELIVERED` (returned to store) |

Delivery OTP rules: valid 10 minutes, 3 attempts per order (a resend does not reset them), an expired OTP doesn't
use an attempt. The OTP is stored only as a hash and is never returned by any API. If the SMS fails, nothing is
used up and the delivery boy can tap again.

All errors have the form `{ "error": { "code": "...", "message": "..." } }`.

## Code layout

```text
src/
  auth/       login OTP, sessions, role guard           (SH-15 to SH-17)
  catalog/    product search                            (U-02)
  maps/       geocoding, road distance, nearest store   (U-06, U-07)
  checkout/   checkout session, server-side pricing     (U-07)
  payment/    Razorpay, payment confirm, webhook        (U-09 to U-12)
  orders/     order creation, status rules, My Orders   (U-11, U-15, SH-19)
  store/      store inbox, order details, dispatch      (S-02, S-05, S-07, S-08)
  delivery/   assigned orders, delivery OTP              (D-02, D-05 to D-08)
  sms/        MSG91 and dev console sender              (SH-14)
  database/   pg wrapper, migrations, staff/product loading (SH-10, SH-12)
  common/     business rules, errors, validation, clock, idempotency keys (SH-21)
migrations/   SQL schema
config/       staff.yaml (hardcoded staff, BR-04) and dev products
```

## Differences from the plan

- **No PostGIS.** The straight-line pre-filter for stores runs in application code. Store count is small,
  so this is fast enough and removes a database extension. Easy to move into SQL later if needed.
- **Road distance is measured from the store to the customer** (the direction the delivery travels).
- **Payment window.** A checkout locks the price and store for 15 minutes. A payment started inside that time
  has its own 15-minute window to be confirmed, so a slow UPI approval near the end of the checkout still
  creates the order. Money confirmed after the window creates no order and is marked for manual refund (EX-09).
- **Staff are keyed by store code and delivery boy code** in `staff.yaml`, not by database IDs. Anyone removed
  from the file is deactivated on the next seed. Staff sessions also remember the login number, so removing
  someone or changing their number ends their session at the next token refresh (within 15 minutes).

## Not done yet

- Flutter screens for the customer (U-01, U-03 to U-05, U-08, U-13, U-14, U-16, U-18). Flutter is not installed on this machine.
- External setup: Razorpay account, Google Maps key with billing, MSG91 DLT templates (U-09, U-17, SH-14).
- Flutter screens for the store manager (S-03, S-04, S-06, S-09, S-10).
- Flutter screens for the delivery boy (D-03, D-04, D-09, D-10).
- "Customer unavailable / refused – return to store" action (D-11, EX-15). Waiting for the BA's decision. Until then an
  order whose customer can't be reached, or whose OTP expired with no resends left, stays "On the way".
- Old rows in `idempotency_keys` (older than 24 hours) are ignored but not yet deleted; add a daily cleanup job.
