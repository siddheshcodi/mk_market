# Implementation Plan – Store (Store Manager) Module

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Module | Store (Store Manager) |
| Inputs | `requirement.md` v1.2, `spec.md` (what to build) |
| Outputs | `tasks.md` (work items), `testcases.md` (tests) |
| Date | 2026-10-08 |
| Status | Draft – stack choice and open items pending (`../tasks.md` SH-01, SH-02) |

---

## 1. Summary

Build the store manager side of the app. The manager logs in with a hardcoded number, sees the orders the system sent to their store, checks the order time and details, and picks a delivery boy from the same store. Picking the delivery boy also sets the order to "On the way for delivery" in the same step. The manager can't reject or cancel orders.

## 2. Technical choices

Uses the same stack as the rest of the app (`../User/plan.md` §2). Specific to this module:

| Area | Choice | Why |
| --- | --- | --- |
| Staff numbers | `config/staff.yaml` in the backend repo, loaded into the database on each deploy | BR-04, A15: changing numbers needs the development team |
| New order refresh | Polling every 5 s while the New tab is open | NFR-08 (within 10 s) without push notifications (A9) |
| Concurrent updates | Conditional database update (`WHERE status = 'PLACED'`) plus a version number | EX-18: first action wins |
| Store isolation | Store ID always taken from the login token, never from the request | NFR-03, BR-15 |

## 3. Code structure

```text
mobile/lib/features/store/
  inbox/                    # S-03, S-04, S-10
  order_details/            # S-06
  assign/                   # S-09

backend/src/
  staff/                    # staff.yaml loading, delivery boys list (SH-12, S-07)
  store-orders/             # store order list, details, dispatch (S-02, S-05, S-08)
  orders/                   # shared order status rules (SH-19)
```

## 4. Key implementation decisions

| # | Decision | Detail | Ref |
| --- | --- | --- | --- |
| 1 | Routing is not done here | The store is chosen at checkout in the User module. This module only reads orders already routed to it | BR-14 |
| 2 | One action to dispatch | A single `dispatch` API sets the delivery boy and status together. There is no separate status-change API | A8, FR-S-05 |
| 3 | Same-store delivery boys only | The server checks that the delivery boy belongs to the manager's store | BR-16 |
| 4 | No reject / cancel / status APIs | Only `dispatch` changes state from this module | FR-S-06, BR-13 |
| 5 | Oldest new orders first | The New tab is sorted oldest first and shows "x min ago", so waiting orders are noticed | D4, EX-11 |
| 6 | Safe retries | `Idempotency-Key` on dispatch, so a double tap or retry doesn't create a second history entry | NFR-11 |
| 7 | Database index | `(store_id, status, placed_at)` keeps the inbox fast | NFR-08 |

Full API details are in `spec.md` §8.

## 5. Dependencies

| Depends on | Needed for | Task |
| --- | --- | --- |
| Store list, manager and delivery boy numbers from the client | Login, assignment | SH-03 |
| Staff loading and role check at login | Login | SH-12, SH-16 |
| Order status rules | Dispatch | SH-19 |
| Paid orders from the User module | Real orders in the inbox | U-11 |
| **Used by** Delivery Boy module | Assigned orders | S-08 → D-02 |
| Undelivered status from Delivery Boy module | Returned tab | D-08 → S-10 |

## 6. Phases and milestones

Assumed team: shares the backend and mobile developers with the other modules; 1 QA from phase 3. Weeks are counted after shared setup.

| Phase | Weeks | Tasks | Milestone (done when) |
| --- | --- | --- | --- |
| 1. Login and inbox | 2–3 | S-01, S-02, S-03, S-04 | Manager logs in and sees only their store's orders, new orders show within 10 s |
| 2. Details and dispatch | 3–4 | S-05 to S-09 | Manager assigns a delivery boy, and the status changes to "On the way" in one step |
| 3. Returned orders | 5 | S-10 | Undelivered orders show in the Returned tab |
| 4. Testing and fixes | 5–7 | S-11 to S-14 | Exit criteria in §7.3 met |

Phase 1 can be built with a test API that creates paid orders, so it doesn't have to wait for User module payment (U-11).

## 7. Testing approach

### 7.1 Levels

| Level | Who | What |
| --- | --- | --- |
| Unit | Developers | Dispatch rules, store isolation, status checks |
| API | Developers / QA | Other store's orders and delivery boys rejected; double dispatch returns a conflict |
| Functional | QA | The 46 cases in `testcases.md` |
| End-to-end | QA | Customer pays → store assigns → delivery boy sees the order |
| Performance / concurrency | QA | Order visible within 10 s (NFR-08); two devices dispatching at once (EX-18) |

### 7.2 Test data

| Data | Details |
| --- | --- |
| Stores | Store A and Store B with known locations |
| Managers | SM-A, SM-B (hardcoded) |
| Delivery boys | DB-A1, DB-A2 (Store A), DB-B1 (Store B) |
| Other numbers | One unregistered number; one customer number |
| Orders | At least 5 paid orders per store, one with several items |
| Devices | Android 13, Android 15, iOS 18+; two phones for concurrency |

### 7.3 Entry and exit

- **Start testing when:** the staff numbers are in the QA build, paid orders can be created, and a basic login → inbox → dispatch run passes.
- **Done when:**
  - all P1 cases pass and at least 95% of P2 cases have been run
  - no Critical or High defects are open
  - no store can see another store's data
  - NFR-08 is met

## 8. Risks

| # | Risk | Mitigation |
| --- | --- | --- |
| R1 | Staff numbers change during testing, which needs a new build | Agree the full test staff list before the first build |
| R2 | Out-of-stock orders (EX-10) can't be closed because there's no reject option | BA decision in SH-01; may become a change request |
| R3 | No way to reassign a delivery boy after dispatch | BA decision in SH-01; change request if needed |
| R4 | Inbox testing blocked if User payment is broken | Test API to create paid orders in QA only |

## 9. Definition of done (per task)

- Code reviewed and merged, and unit tests pass
- Every query is limited to the manager's own store
- API matches `spec.md`, with standard errors and messages
- Works on one Android and one iOS test device
- Related test cases in `testcases.md` pass in the QA environment
