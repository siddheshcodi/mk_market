# Tasks – Store (Store Manager) Module

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Module | Store (Store Manager) |
| Source | `requirement.md` v1.2, `spec.md`, `plan.md`, `testcases.md` |
| Date | 2026-10-08 |
| Shared tasks | `../tasks.md` (IDs starting `SH-`) |

**Estimates** are in person-days. **Owner:** BE = backend, FE = mobile, QA = testing.
**Status:** [x] done, [~] partly done (see backend/README.md "Not done yet"), [ ] not started.

---

## 1. Login

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S-01 | Store manager login flow | Shared login screens with role `STORE_MANAGER`; only hardcoded numbers; token carries store ID; show store name after login | SH-12, SH-16, SH-18 | 1 | FE / BE | FR-S-01, US-06, BR-04 | [~] backend |

## 2. Receiving orders

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S-02 | Store orders list API | `GET /store/orders` by status (Placed, On the way, Undelivered, Delivered); only the store's own orders; index for fast loading | SH-19, SH-20, U-11 | 2 | BE | FR-S-02, FR-S-03, BR-14 | [x] |
| S-03 | Order inbox screen | Tabs: New, On the way, Returned, Delivered; cards with order ID, order placed time, items count, amount, area | S-02, SH-07 | 3 | FE | FR-S-03, US-07 | [ ] |
| S-04 | Quick refresh | Poll New tab every 5 s while open, pull to refresh, highlight new orders, sound / vibration in app | S-03 | 1 | FE | NFR-08, A9 | [ ] |

## 3. Order details

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S-05 | Order details API | `GET /store/orders/{id}`: items, amount, customer name and mobile, address, placed time, delivery boy, timeline, undelivered reason | S-02 | 1 | BE | FR-S-04, D4 | [x] |
| S-06 | Order details screen | Show placed time clearly (date, time, minutes ago); tap to call customer; map link; no reject or cancel button | S-05 | 2 | FE | FR-S-04, FR-S-06, EX-10 | [ ] |

## 4. Assign delivery boy

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S-07 | Delivery boys list API | `GET /store/delivery-boys`: active delivery boys of this store only, with active order count | SH-12 | 0.5 | BE | FR-S-05, BR-16, A7 | [x] |
| S-08 | Dispatch API | `POST /store/orders/{id}/dispatch`: check order is the store's and "Placed", delivery boy is from the same store; set delivery boy and "On the way for delivery" in one step; first action wins; safe on retry | SH-19, SH-21, S-07 | 2 | BE | FR-S-05, BR-15, BR-16, A8, EX-18 | [x] |
| S-09 | Assign screen | Pick one delivery boy, "Confirm – Send for delivery"; block confirm without a choice; show "already updated" message on conflict | S-06, S-08 | 2 | FE | US-08 | [ ] |

## 5. Returned orders

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S-10 | Returned tab | Show Undelivered orders with reason and "Returned to store – refund handled manually"; read only | S-03, D-08 | 1 | FE | BR-21, D6 | [ ] |

## 6. Testing

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S-11 | Unit and API tests | Store isolation, cross-store delivery boy rejected, double dispatch, status rules | S-02 to S-08 | 2 | BE | – | [x] |
| S-12 | Test data setup | Two stores, managers, delivery boys, paid orders for each store | SH-12 | 1 | QA | plan.md §7.2 | [ ] |
| S-13 | Run test cases | Run the 46 cases in `testcases.md`, log defects, retest | All above | 10 | QA | plan.md §7 | [ ] |
| S-14 | Performance and concurrency check | Order visible within 10 s (NFR-08); two devices assigning at once (EX-18) | S-13 | 1 | QA | NFR-08, EX-18 | [ ] |

## Summary

| Area | Est. (person-days) |
| --- | --- |
| Login | 1 |
| Receiving orders | 6 |
| Order details | 3 |
| Assign delivery boy | 4.5 |
| Returned orders | 1 |
| Testing | 14 |
| **Total** | **29.5** |

## Order of work

1. S-01 and S-07 can start once shared login and staff loading (SH-12, SH-16) are done.
2. S-02 needs orders from the User module (U-11) for real testing.
3. S-08 (dispatch) must be done before Delivery Boy module work on assigned orders (D-02) can be tested.
4. S-10 needs the Undelivered status from the Delivery Boy module (D-08).
