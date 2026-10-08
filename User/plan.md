# Implementation Plan – User (Customer) Module

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Module | User (Customer) |
| Inputs | `requirement.md` v1.2, `spec.md` (what to build) |
| Outputs | `tasks.md` (work items), `testcases.md` (tests) |
| Date | 2026-10-08 |
| Status | Draft – stack choice and open items pending (`../tasks.md` SH-01, SH-02) |

---

## 1. Summary

Build the customer side of the app: login with mobile number and OTP, product search, address entry, a check that a store is within 4 km by road, full advance payment, and order tracking. An order is created only after the payment gateway confirms payment, and it's sent to the nearest store that was locked at checkout.

## 2. Technical choices

Proposed stack, to be confirmed in SH-02:

| Area | Choice | Why |
| --- | --- | --- |
| Mobile | Flutter (one app for Android and iOS) | A13: one app for both platforms, with a separate view for each role |
| Backend | NestJS (Node.js, TypeScript), REST | Separate modules per feature, easy to test |
| Database | PostgreSQL 16 + PostGIS + `pg_trgm` | Transactions for payment and orders; finding nearby stores; fast name search (NFR-07) |
| Maps | Google Geocoding + Distance Matrix (driving) | BR-08 needs road distance |
| Payment | Razorpay (UPI, card, net banking), mobile SDK + webhook | A1, BR-09; card data stays with the gateway (NFR-05) |
| SMS | MSG91 with DLT templates | Login OTP and delivery OTP (NFR-09) |
| Status refresh | Polling every 15 s while the order screen is open | No push notifications in scope (A9) |

## 3. Code structure

```text
mobile/lib/
  core/                     # shared: API client, auth, errors, theme (SH-07)
  features/customer/
    search/                 # U-03, U-04
    address/                # U-05, U-08
    payment/                # U-13, U-14
    orders/                 # U-16, U-18

backend/src/
  auth/                     # shared login OTP (SH-15 to SH-17)
  catalog/                  # product search (U-02)
  serviceability/           # geocoding, road distance, nearest store (U-06, U-07)
  checkout/                 # checkout session, server pricing (U-07)
  payment/                  # gateway order, confirm, webhook (U-09 to U-12)
  orders/                   # order creation, customer order APIs (U-11, U-15)
```

## 4. Key implementation decisions

| # | Decision | Detail | Ref |
| --- | --- | --- | --- |
| 1 | Server decides the price | The app sends product IDs and quantities only. The server calculates the amount and locks it in the checkout | BR-09, NFR-05 |
| 2 | Two-step store search | Stores within 4 km straight-line first (fast database query), then road distance only for those few; pick the nearest at or under 4,000 m | BR-08, BR-14 |
| 3 | Store locked at checkout | The chosen store is saved in the checkout (valid 15 min) and copied to the order on payment, so the order goes to the store that was checked | BR-14 |
| 4 | Two payment confirmation paths, one order | The app confirm call and the gateway webhook can both create the order. A unique gateway payment ID makes sure only one does | BR-10, NFR-11 |
| 5 | Order and payment saved together | Payment capture and order "Placed" are saved in one database transaction, so the order shows at the store right away | NFR-08 |
| 6 | Late payments | A payment confirmed after the checkout expired creates no order and is flagged for manual refund | EX-09, BR-12 |
| 7 | Money in paise | Whole numbers only, no decimals | – |
| 8 | Maps failure is not "serviceable" | If the maps API fails, show a retry message and never allow payment | BR-08 |

Full API and data details are in `spec.md` §8–§9.

## 5. Dependencies

| Depends on | Needed for | Task |
| --- | --- | --- |
| Shared login, sessions, order status rules | Login, order creation | SH-15 to SH-21 |
| Product data loaded | Search | SH-13 |
| Store list with locations | 4 km check | SH-03, SH-12 |
| Payment gateway account and sandbox keys | Payment | U-09 |
| Maps API key with billing | 4 km check | U-06 |
| SMS DLT approval (can take 1–2 weeks) | Login OTP, delivery OTP | SH-14 |
| **Used by** Store module | Orders reach the store | U-11 → S-02 |

Start the payment gateway account, maps billing and SMS DLT registration in week 1. These external approvals take the longest.

## 6. Phases and milestones

Assumed team: 1 backend and 1 mobile developer on this module, 1 QA from phase 3. Durations are in weeks after the shared setup (`../tasks.md` §2–§4) is done.

| Phase | Weeks | Tasks | Milestone (done when) |
| --- | --- | --- | --- |
| 1. Login and search | 1–2 | U-01, U-02, U-03, U-04 | Customer can log in, search and select products |
| 2. Address and 4 km check | 2–3 | U-05, U-06, U-07, U-08 | Correct store chosen for test addresses; "no store" message works |
| 3. Payment and orders | 3–5 | U-09 to U-14 | Sandbox payment creates exactly one "Placed" order; failures create none |
| 4. Order tracking | 5–6 | U-15 to U-18 | Customer sees status changes made by Store and Delivery Boy modules |
| 5. Testing and fixes | 6–8 | U-19 to U-22 | Exit criteria in §7.3 met |

## 7. Testing approach

### 7.1 Levels

| Level | Who | What |
| --- | --- | --- |
| Unit | Developers | Address checks, store selection, price calculation, payment signature check |
| API | Developers / QA | All customer endpoints; tampered amount, other customers' order IDs |
| Functional | QA | The 83 cases in `testcases.md` |
| End-to-end | QA | Full flow with Store and Delivery Boy modules (`../tasks.md` SH-22) |
| Performance | QA | Search under 2 s (NFR-07), order at store within 10 s (NFR-08), OTP SMS under 30 s (NFR-09) |

### 7.2 Test data

| Data | Details |
| --- | --- |
| Customers | One new number, one existing number, a second customer to check customers can't see each other's orders |
| Products | At least 4, including similar names ("Milk 1L", "Milk 500ml") |
| Addresses | Stores at 2.5 km and 3.8 km by road; 3.5 km straight-line but 4.6 km by road; exactly 4.0 km and 4.1 km by road; more than 10 km away |
| Payments | Sandbox success, failure, cancel, timeout and "debited but not confirmed" |
| Devices | Android 10, 13, 15; iOS 16 and 18+; Wi-Fi, 4G, slow 3G |

### 7.3 Entry and exit

- **Start testing when:** the QA build is installed, the sandbox payment, SMS and maps keys work, test data is loaded, and a basic login → search → pay run passes.
- **Done when:**
  - all P1 cases pass and at least 95% of P2 cases have been run
  - no Critical or High defects are open
  - NFR-07, NFR-08 and NFR-09 targets are met

## 8. Risks

| # | Risk | Mitigation |
| --- | --- | --- |
| R1 | DLT or payment gateway approval delays | Apply in week 1; use the sandbox and a test SMS route until approved |
| R2 | Road distances change in the maps data | Recheck test addresses before each test cycle |
| R3 | Maps API cost per checkout | Straight-line filter first; cache road distance per address and store for a short time |
| R4 | Open BRD items (session timeout, OTP rate limit, late payments) | Close in SH-01 before phase 3 |
| R5 | Order tracking depends on Store and Delivery Boy modules | Phase 4 planned after S-08 and D-07 are ready |

## 9. Definition of done (per task)

- Code reviewed and merged, and unit tests pass
- API matches `spec.md`, and errors use the standard format and messages
- No personal data or OTPs in logs
- Works on one Android and one iOS test device
- Related test cases in `testcases.md` pass in the QA environment
