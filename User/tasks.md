# Tasks – User (Customer) Module

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Module | User (Customer) |
| Source | `requirement.md` v1.2, `spec.md`, `plan.md`, `testcases.md` |
| Date | 2026-10-08 |
| Shared tasks | `../tasks.md` (IDs starting `SH-`) |

**Estimates** are in person-days. **Owner:** BE = backend, FE = mobile, QA = testing.
**Status:** [x] done, [~] partly done (see backend/README.md "Not done yet"), [ ] not started.

---

## 1. Login

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U-01 | Customer login flow | Use shared login screens with role `USER`; create customer account on first login; land on search screen | SH-15, SH-18 | 1 | FE / BE | FR-U-01, FR-U-02, US-01 | [~] backend |

## 2. Product search and selection

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U-02 | Search API | `GET /products/search`: name match, not case sensitive, paged; under 2 s for 95% | SH-13 | 2 | BE | FR-U-03, FR-U-04, NFR-07 | [x] |
| U-03 | Search screen | Search box, results with name, unit, price, image; "No products found" | U-02, SH-07 | 2 | FE | US-02, EX-05 | [ ] |
| U-04 | Product selection | Add / remove products, set quantity, show total; block proceed with 0 products; no delivery charge | U-03 | 2 | FE | FR-U-05, BR-05, BR-23 | [ ] |

## 3. Address and store check

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U-05 | Address screen | House no., street/area, landmark, city, pincode (6 digits) and map pin; highlight missing fields | U-04 | 2.5 | FE | FR-U-06, BR-06, BR-07, EX-06 | [ ] |
| U-06 | Maps integration | Geocoding and road distance (driving) API client, error handling | SH-05 | 1.5 | BE | BR-08, D2 | [x] |
| U-07 | Store check and checkout API | `POST /checkout`: check address, find stores within 4 km straight-line, then pick nearest by road (≤ 4 km); recalculate price on server; lock store and amount for 15 min | U-06, SH-11 | 3 | BE | FR-U-07, FR-U-08, BR-08, BR-14 | [x] |
| U-08 | "No store" handling | Show "Currently no store is available in your area"; block payment; show retry message if maps API fails | U-05, U-07 | 0.5 | FE | FR-U-08, EX-07, D3 | [ ] |

## 4. Payment and order creation

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U-09 | Payment gateway setup | Gateway account, sandbox keys, webhook endpoint with signature check; UPI, card, net banking only | SH-05 | 1.5 | BE | BR-09, NFR-05, A1 | [~] code; account pending |
| U-10 | Payment APIs | `POST /checkout/{id}/payment` (create gateway order with server amount), `POST /checkout/{id}/payment/confirm` (check signature and amount) | U-07, U-09 | 2.5 | BE | FR-U-09, BR-10 | [x] |
| U-11 | Order creation on payment success | Create order "Placed" with locked store only after confirmed payment; webhook and app confirm both handled; one order per payment | U-10, SH-19, SH-21 | 2.5 | BE | FR-U-10, BR-10, NFR-11 | [x] |
| U-12 | Failed / missing payment handling | Failed, cancelled, timed-out: no order. Late confirmation after checkout expiry: no order, flag for manual refund | U-11 | 1.5 | BE | BR-11, EX-08, EX-09, BR-12 | [x] |
| U-13 | Payment screens | Open gateway SDK, "Confirming payment…" state, failure message with Retry, confirmation with order ID | U-10, U-08 | 3 | FE | US-04, FR-U-11 | [ ] |
| U-14 | Recover after app close | On reopen, check any open checkout and show the result | U-13 | 1 | FE | NFR-11 | [ ] |

## 5. My orders and status

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U-15 | Orders API | `GET /orders`, `GET /orders/{id}`; only the customer's own orders; status timeline | SH-19, SH-20 | 1.5 | BE | FR-U-12, NFR-03 | [x] |
| U-16 | My Orders screens | List and details with status, refresh every 15 s on screen, pull to refresh; no cancel option anywhere | U-15 | 2.5 | FE | FR-U-12, FR-U-14, US-05 | [ ] |

## 6. Delivery OTP for the customer

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U-17 | Delivery OTP SMS template | DLT-approved text sent to the customer's registered number (sending is done by Delivery Boy module task D-05) | SH-14 | 0.5 | BE | FR-U-13, BR-18 | [~] code; DLT template pending |
| U-18 | "Share the OTP" message | Show on order details while a delivery OTP is active | U-16 | 0.5 | FE | FR-U-13 | [~] backend |

## 7. Testing

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| U-19 | Unit and API tests | Address checks, store check, payment signature, one order per payment, own-orders-only | U-02 to U-15 | 3 | BE | – | [x] |
| U-20 | Test data setup | Customers, products, stores and addresses at known road distances, sandbox payment cards | SH-12, SH-13 | 2 | QA | plan.md §7.2 | [ ] |
| U-21 | Run test cases | Run the 83 cases in `testcases.md`, log defects, retest | All above | 14 | QA | plan.md §7 | [ ] |
| U-22 | Performance check | Search under 2 s (NFR-07), order at store within 10 s (NFR-08), OTP SMS under 30 s (NFR-09) | U-21 | 2 | QA | NFR-07 to NFR-09 | [ ] |

## Summary

| Area | Est. (person-days) |
| --- | --- |
| Login | 1 |
| Search and selection | 6 |
| Address and store check | 7.5 |
| Payment and order creation | 12 |
| My orders | 4 |
| Delivery OTP | 1 |
| Testing | 21 |
| **Total** | **52.5** |

## Order of work

1. U-02, U-06, U-09 can start in parallel once shared setup is done.
2. U-07 (store check) before U-10 (payment) before U-11 (order creation).
3. U-11 must be done before Store module work on receiving orders (S-02) can be tested.
