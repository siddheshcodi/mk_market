# Test Cases – Store (Store Manager) Module

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Module | Store (Store Manager) |
| Source | `requirement.md` v1.2 (BRD, 2026-10-07) |
| Prepared by | QA |
| Date | 2026-10-07 |

**Priority:** P1 = critical (blocks release), P2 = high, P3 = medium.
**Type:** F = functional, N = negative, B = boundary, S = security, P = performance, U = usability, I = integration.

---

## 1. Test data and environment

| Data | Value |
| --- | --- |
| Store A manager | Hardcoded number SM-A (e.g. 9000000001) |
| Store B manager | Hardcoded number SM-B (e.g. 9000000002) |
| Store A delivery boys | DB-A1, DB-A2 |
| Store B delivery boy | DB-B1 |
| Unregistered number | 9111111111 (not in hardcoded list) |
| Customer | 9876543210 with Address-1 (nearest store: Store A) |
| Login OTP | 6 digits, valid 5 minutes, resend after 30 seconds |

---

## 2. Login (FR-S-01, US-06, BR-04, FR-G-02, EX-04)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-S-001 | Login with hardcoded number and correct OTP | SM-A in hardcoded list | 1. Select Store Manager. 2. Enter SM-A. 3. Get OTP. 4. Enter OTP | Logged in to Store A's order screen | P1 | F | FR-S-01, US-06 AC1 |
| TC-S-002 | Unregistered number | – | Select Store Manager, enter 9111111111, Get OTP | "This number is not registered". No OTP sent | P1 | N | US-06 AC2, EX-04, FR-G-02 |
| TC-S-003 | Customer number tries store login | Customer 9876543210 exists | Select Store Manager, enter 9876543210 | "This number is not registered". No OTP sent | P1 | S | BR-04 |
| TC-S-004 | Delivery boy number tries store login | DB-A1 is hardcoded as delivery boy | Select Store Manager, enter DB-A1 number | "This number is not registered" or access only to delivery module. Never store access | P1 | S | NFR-03 |
| TC-S-005 | No sign-up option | – | Check store login screens | No sign-up / register option for store managers | P2 | F | BR-04 |
| TC-S-006 | Wrong OTP | OTP requested | Enter wrong OTP | Error. Can retry or resend. No lock | P1 | N | BR-03 |
| TC-S-007 | Expired OTP | OTP requested | Enter OTP after 5 minutes | Expired error. Resend available | P2 | B | BR-02 |
| TC-S-008 | Invalid number format | – | Enter 9-digit number | "Enter a valid 10-digit mobile number". No OTP | P2 | N | BR-01, EX-01 |
| TC-S-009 | Number change needs development | – | Check app for a way to add or change manager numbers | No such option in the app | P3 | F | FR-G-02, A15 |

## 3. Receiving orders (FR-S-02, FR-S-03, US-07, BR-14, NFR-08)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-S-010 | New order appears in nearest store | SM-A and SM-B logged in | Customer at Address-1 pays for an order | Order shows in Store A's new orders list | P1 | I | FR-S-02, FR-S-03, US-07 AC1 |
| TC-S-011 | Order not shown in other stores | As TC-S-010 | Check Store B's list | Order not shown in Store B | P1 | I/S | BR-14, US-07 AC1 |
| TC-S-012 | Order arrives within 10 seconds | SM-A logged in on order list | Customer completes payment, time it | Order appears within 10 seconds | P1 | P | NFR-08 |
| TC-S-013 | Unpaid order not received | SM-A logged in | Customer starts payment, then cancels | No order appears in Store A | P1 | N/I | BR-10, BR-11 |
| TC-S-014 | Failed payment not received | SM-A logged in | Customer payment fails | No order appears | P1 | N/I | BR-11 |
| TC-S-015 | Each order goes to exactly one store | Address within 4 km of Store A and B | Place an order | Order appears in exactly one store (the nearest by road) | P1 | I | BR-14 |
| TC-S-016 | Several new orders | 3 orders placed for Store A | Open new orders list | All 3 shown | P2 | F | FR-S-03 |

## 4. Order details and order time (FR-S-04, US-07 AC2, D4)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-S-017 | Order details shown | Order for Store A | Open the order | Order ID, items, delivery address and order placed time shown | P1 | F | FR-S-04, US-07 AC2 |
| TC-S-018 | Order placed time is correct | Order placed at a known time | Compare shown time with the payment success time | Times match (correct date, time and time zone IST) | P1 | F | FR-S-04, D4 |
| TC-S-019 | Customer details visible to store | Order for Store A | Open the order | Customer name, mobile number and address visible | P2 | F | Section 2 permission matrix |
| TC-S-020 | Items and quantities correct | Customer ordered 2 × Bread, 1 × Milk 1L | Open the order | Items and quantities match the customer's order | P1 | F | FR-S-04 |

## 5. Assign delivery boy (FR-S-05, US-08, BR-15, BR-16, A7, A8)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-S-021 | Assign delivery boy | Order "Placed" in Store A | Select DB-A1, confirm | Status becomes "On the way for delivery" in the same action | P1 | F | FR-S-05, US-08 AC1, A8 |
| TC-S-022 | Order appears for the delivery boy | TC-S-021 done | DB-A1 opens their order list | Order shown in DB-A1's list | P1 | I | US-08 AC2 |
| TC-S-023 | Other delivery boy can't see it | TC-S-021 done | DB-A2 opens their list | Order not shown | P1 | I/S | BR-16, BR-17 |
| TC-S-024 | Only own store's delivery boys listed | SM-A logged in | Open assign list | Only DB-A1 and DB-A2 shown. DB-B1 not shown | P1 | F/S | FR-S-05, BR-16 |
| TC-S-025 | Assign other store's delivery boy via API | SM-A token | Call assign with DB-B1's ID | Rejected | P1 | S | BR-16 |
| TC-S-026 | No separate status change | Order "Placed" | Look for a status dropdown | No way to change status without assigning a delivery boy | P2 | F | A8 |
| TC-S-027 | Confirm without choosing a delivery boy | Order "Placed" | Open assign, tap confirm without selection | Blocked. Asked to choose a delivery boy | P2 | N | FR-S-05 |
| TC-S-028 | Assign an already assigned order | Order "On the way for delivery" | Try assigning again | Not allowed. Order assigned to one delivery boy only | P1 | N | BR-16, BR-22 |
| TC-S-029 | No limit on orders per delivery boy | DB-A1 already has 5 active orders | Assign a 6th order to DB-A1 | Assignment allowed | P3 | B | A7 |
| TC-S-030 | Other store manager can't assign | Order for Store A | SM-B tries to assign it (via API with order ID) | Rejected / not found | P1 | S | BR-15, NFR-03 |
| TC-S-031 | Two managers / devices act at once | Same order open on two devices for Store A | Assign on both at the same time | Only the first saved. Second sees the updated status | P2 | N | EX-18 |
| TC-S-032 | Double tap on confirm | Order "Placed" | Tap confirm twice quickly | One assignment and one status change only | P2 | N | NFR-11 |

## 6. No reject or cancel (FR-S-06, BR-13, D5)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-S-033 | No reject option | Order "Placed" | Check list and details screens | No reject option | P1 | N | FR-S-06, US-07 AC3 |
| TC-S-034 | No cancel option | Orders in every status | Check screens | No cancel option | P1 | N | BR-13 |
| TC-S-035 | Status can't go backwards | Order "On the way for delivery" | Try to set it back to "Placed" (UI or API) | Not allowed | P1 | N | BR-22, FR-G-01 |
| TC-S-036 | Store can't set "Delivered" | Order "On the way for delivery" | Try to set "Delivered" (UI or API) | Not allowed. Only the OTP flow can deliver | P1 | S | BR-20, FR-G-01 |

## 7. Waiting, stock and returned orders (EX-10, EX-11, EX-12, BR-21)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-S-037 | Order not acted on | Order "Placed" | Leave it for several hours | Stays "Placed". No automatic change or rejection | P2 | F | EX-11 |
| TC-S-038 | No delivery boy available | Order "Placed" | Don't assign | Order stays "Placed" with the store | P2 | F | EX-12 |
| TC-S-039 | Out of stock after payment | Order "Placed", item out of stock | Manager uses customer's mobile shown in the order to call | Customer mobile available to call. Refund handled outside the app | P3 | F | EX-10, A6 |
| TC-S-040 | Undelivered order returned to store | Delivery boy enters wrong OTP 3 times | Store manager checks order | Order shows "Undelivered" and is visible to the store | P2 | I | BR-21, FR-D-10 |
| TC-S-041 | No refund option | Undelivered order | Check screens | No refund option in the app | P3 | F | BR-12 |

## 8. Security and usability (NFR-01, NFR-03, NFR-12)

| TC ID | Scenario | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- |
| TC-S-042 | Manager can't use customer features | Logged in as SM-A, try to search or place an order | Not available | P1 | S | Section 2, NFR-03 |
| TC-S-043 | Manager can't use delivery features | Logged in as SM-A, try delivery OTP screens / APIs | Access denied | P1 | S | NFR-03 |
| TC-S-044 | Store data isolation | SM-A opens Store B's order ID directly | Not found / denied | P1 | S | NFR-03 |
| TC-S-045 | Encrypted traffic | Capture traffic | HTTPS (TLS 1.2+) only | P1 | S | NFR-01 |
| TC-S-046 | Clear error messages | Trigger each store error | Message says what went wrong and what to do next | P2 | U | NFR-12 |

---

## Summary

| Area | Count |
| --- | --- |
| Login | 9 |
| Receiving orders | 7 |
| Order details | 4 |
| Assign delivery boy | 12 |
| No reject or cancel | 4 |
| Waiting, stock, returned | 5 |
| Security and usability | 5 |
| **Total** | **46** |
