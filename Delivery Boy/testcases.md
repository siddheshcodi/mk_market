# Test Cases – Delivery Boy Module

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Module | Delivery Boy |
| Source | `requirement.md` v1.2 (BRD, 2026-10-07) |
| Prepared by | QA |
| Date | 2026-10-07 |

**Priority:** P1 = critical (blocks release), P2 = high, P3 = medium.
**Type:** F = functional, N = negative, B = boundary, S = security, P = performance, U = usability, I = integration.

---

## 1. Test data and environment

| Data | Value |
| --- | --- |
| Delivery boys, Store A | DB-A1 (e.g. 9000000011), DB-A2 (e.g. 9000000012), hardcoded |
| Delivery boy, Store B | DB-B1 (e.g. 9000000021), hardcoded |
| Unregistered number | 9111111111 |
| Customer | 9876543210, Address-1, order assigned to DB-A1 |
| Login OTP | 6 digits, valid 5 minutes, resend after 30 seconds |
| Delivery OTP | 4 digits, valid 10 minutes, 3 attempts, 2 resends |

---

## 2. Login (FR-D-01, US-06, BR-04, FR-G-02, EX-04)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-D-001 | Login with hardcoded number and correct OTP | DB-A1 hardcoded | 1. Select Delivery Boy. 2. Enter DB-A1. 3. Get OTP. 4. Enter OTP | Logged in to the delivery order list | P1 | F | FR-D-01, US-06 AC1 |
| TC-D-002 | Unregistered number | – | Enter 9111111111, Get OTP | "This number is not registered". No OTP sent | P1 | N | US-06 AC2, EX-04 |
| TC-D-003 | Customer number tries delivery login | Customer 9876543210 exists | Select Delivery Boy, enter 9876543210 | "This number is not registered". No OTP | P1 | S | BR-04 |
| TC-D-004 | Store manager number tries delivery login | SM-A hardcoded as manager | Select Delivery Boy, enter SM-A | Not given delivery access | P1 | S | NFR-03 |
| TC-D-005 | No sign-up option | – | Check login screens | No register option for delivery boys | P2 | F | BR-04 |
| TC-D-006 | Wrong login OTP | OTP requested | Enter wrong OTP | Error. Retry or resend allowed. No lock | P1 | N | BR-03 |
| TC-D-007 | Expired login OTP | OTP requested | Enter OTP after 5 minutes | Expired error | P2 | B | BR-02 |

## 3. Assigned orders (FR-D-02, FR-D-03, US-09, BR-17, NFR-04)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-D-008 | Assigned order shown | Store A assigns order to DB-A1 | DB-A1 opens order list | Order shown | P1 | F/I | FR-D-02, US-08 AC2 |
| TC-D-009 | Unassigned orders not shown | Store A has "Placed" orders not yet assigned | DB-A1 opens list | Unassigned orders not shown | P1 | N | FR-D-02 |
| TC-D-010 | Other delivery boy's order not shown | Order assigned to DB-A1 | DB-A2 opens list | Order not shown | P1 | S | US-09 AC2, BR-17 |
| TC-D-011 | Other store's order not shown | Order assigned to DB-B1 | DB-A1 opens list | Order not shown | P1 | S | BR-17 |
| TC-D-012 | Open other delivery boy's order directly | DB-A2 logged in | Open DB-A1's order ID via API / deep link | Not found / denied | P1 | S | BR-17, NFR-03 |
| TC-D-013 | Customer details shown | Order assigned to DB-A1 | Open the order | Customer name, mobile number and full delivery address shown | P1 | F | FR-D-03, US-09 AC1 |
| TC-D-014 | Customer details are correct | As above | Compare with what the customer entered | Name, mobile and address match exactly | P1 | F | FR-D-03 |
| TC-D-015 | Customer details hidden after delivery | Order "Delivered" | DB-A1 opens the order again | Customer address and mobile no longer visible | P2 | S | NFR-04 |
| TC-D-016 | Customer details hidden after undelivered | Order "Undelivered" | DB-A1 opens the order again | Customer address and mobile no longer visible | P2 | S | NFR-04 |
| TC-D-017 | Several assigned orders | 3 orders assigned to DB-A1 | Open list | All 3 shown | P2 | F | A7 |

## 4. Mark as Delivered and send OTP (FR-D-04, FR-D-05, FR-U-13, US-10, BR-18)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-D-018 | Tap Delivered | Order "On the way for delivery", assigned to DB-A1 | Tap "Delivered" | 4-digit OTP sent to customer's registered mobile. OTP entry screen opens | P1 | F/I | FR-D-04, FR-D-05, US-10 |
| TC-D-019 | OTP not shown to delivery boy | TC-D-018 done | Check every screen of the delivery app | OTP value not shown anywhere | P1 | S | NFR-02 |
| TC-D-020 | OTP sent only to registered number | Delivery address has different contact | Tap Delivered | SMS only to the customer's login number | P1 | S | BR-18 |
| TC-D-021 | OTP format | TC-D-018 done | Check customer SMS | OTP is 4 digits | P2 | B | BR-19 |
| TC-D-022 | OTP SMS speed | – | Repeat TC-D-018 20 times | At least 95% of SMS arrive within 30 seconds | P2 | P | NFR-09 |
| TC-D-023 | OTP unique per order | Two orders for the same customer | Tap Delivered on both | Each order gets its own OTP. OTP of order 1 doesn't work for order 2 | P1 | S | BR-19 |
| TC-D-024 | Status not changed by tapping Delivered alone | TC-D-018 done | Check status in customer and store apps | Not "Delivered" until correct OTP is entered | P1 | F | BR-20 |
| TC-D-025 | Double tap on Delivered | Order on the way | Tap Delivered twice quickly | Only one OTP SMS sent | P2 | N | NFR-11 |

## 5. Enter OTP (FR-D-06, FR-D-07, FR-D-08, US-11, BR-19, BR-20, EX-13)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-D-026 | Correct OTP | OTP sent | Enter OTP from customer's SMS, submit | Status becomes "Delivered" (in delivery, store and customer apps) | P1 | F/I | FR-D-07, US-11 AC1 |
| TC-D-027 | Wrong OTP once | OTP sent | Enter wrong OTP | "Incorrect OTP". Status not "Delivered". Can try again | P1 | N | FR-D-08, US-11 AC2, EX-13 |
| TC-D-028 | Wrong OTP twice, then correct | OTP sent | 1. Wrong. 2. Wrong. 3. Correct | Status becomes "Delivered" | P1 | B | FR-D-08 |
| TC-D-029 | Wrong OTP 3 times | OTP sent | Enter wrong OTP 3 times | Status "Undelivered". Order returned to store. No more attempts | P1 | B | FR-D-10, US-11 AC4 |
| TC-D-030 | Correct OTP after 3 wrong | TC-D-029 done | Try entering the correct OTP | Not accepted. Order stays "Undelivered" | P1 | N | FR-D-10, BR-21 |
| TC-D-031 | OTP with 3 digits | OTP sent | Enter 123, submit | Blocked or error. Doesn't use an attempt (expected behaviour to confirm) | P3 | B | BR-19 |
| TC-D-032 | OTP with letters | OTP sent | Enter 12a4 | Not accepted | P3 | N | BR-19 |
| TC-D-033 | Expired OTP | OTP sent | Enter correct OTP after 10 minutes | Rejected as expired. Order not "Delivered". Resend available | P1 | B | BR-19 |
| TC-D-034 | OTP just before expiry | OTP sent | Enter correct OTP at 9 min 50 s | Status becomes "Delivered" | P2 | B | BR-19 |
| TC-D-035 | OTP single use | Order delivered | Try submitting the same OTP again (API) | Rejected. Order stays "Delivered" | P2 | S | BR-19 |
| TC-D-036 | Other order's OTP | Two active orders for DB-A1 | Enter order 1's OTP on order 2 | "Incorrect OTP" | P1 | S | BR-19 |
| TC-D-037 | OTP brute force | OTP sent | Try more than 3 OTPs quickly (UI or API) | No more than 3 attempts counted. Then "Undelivered" | P1 | S | BR-19, NFR-02 |

## 6. Resend OTP (FR-D-09, US-11 AC3, EX-14)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-D-038 | Resend once | OTP sent | Tap Resend | Customer gets a new OTP | P1 | F | FR-D-09, US-11 AC3, EX-14 |
| TC-D-039 | Resend twice | First resend done | Tap Resend again | Customer gets another new OTP | P1 | B | FR-D-09 |
| TC-D-040 | Third resend blocked | 2 resends done | Try Resend again | Not allowed. Message no resends left | P1 | B | FR-D-09, BR-19 |
| TC-D-041 | New OTP works after resend | Resent | Enter the newest OTP | Status becomes "Delivered" | P1 | F | FR-D-09 |
| TC-D-042 | Old OTP after resend | Resent | Enter the older OTP | Rejected (expected behaviour to confirm with BA) | P2 | S | BR-19 |
| TC-D-043 | Attempts after resend | 2 wrong attempts, then resend | Enter wrong OTP once more | Check whether order becomes "Undelivered" (3 attempts total) or more tries allowed. **BRD unclear, confirm with BA** | P2 | B | BR-19 |

## 7. Undelivered and returned to store (FR-D-10, BR-21, EX-15, D6)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-D-044 | Undelivered order goes back to store | TC-D-029 done | Store manager checks orders | Order shows as "Undelivered" in Store A | P1 | I | FR-D-10, BR-21 |
| TC-D-045 | Undelivered is final | Order "Undelivered" | Try to make it "Delivered" or "On the way" (UI or API) | Not allowed | P1 | N | Section 5.2, BR-22 |
| TC-D-046 | Customer sees Undelivered | Order "Undelivered" | Customer opens My Orders | Status "Undelivered" | P2 | I | FR-U-12 |
| TC-D-047 | No refund action | Order "Undelivered" | Check delivery app | No refund option | P3 | F | BR-12 |
| TC-D-048 | Customer not available or refuses | Order on the way, customer doesn't answer | Try to close the order without OTP | Order not "Delivered". **BRD doesn't give the delivery boy a "mark undelivered" action, confirm expected flow with BA** | P2 | N | EX-15 |

## 8. Network and concurrent actions (EX-17, EX-18, NFR-11)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-D-049 | Network lost while submitting OTP | OTP sent | Turn off data, submit correct OTP | Status not changed. Error shown. Can retry | P1 | N | EX-17 |
| TC-D-050 | Retry after network returns | TC-D-049 done | Turn on data, submit again | Status "Delivered". Only one status change recorded | P1 | N | EX-17, NFR-11 |
| TC-D-051 | Network drops after server accepts | OTP sent | Submit correct OTP, cut data before response | After reconnecting, order shows "Delivered". No extra attempt used | P1 | N | NFR-11 |
| TC-D-052 | Same account on two phones | DB-A1 logged in on two devices | Submit OTP on both at the same time | Only the first valid action saved. Other sees updated status | P2 | N | EX-18 |
| TC-D-053 | App closed after tapping Delivered | OTP sent | Kill app, reopen | Order still on the way. OTP screen reachable. Attempt and resend counts kept | P2 | N | NFR-11 |

## 9. Security and usability (NFR-01, NFR-02, NFR-03, NFR-12)

| TC ID | Scenario | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | 
| TC-D-054 | Delivery boy can't use customer features | Try to search or place an order | Not available | P1 | S | NFR-03 |
| TC-D-055 | Delivery boy can't assign orders | Try store screens / assign API | Access denied | P1 | S | NFR-03 |
| TC-D-056 | OTP not in API responses or logs | Inspect API responses and server logs after Delivered and resend | OTP value not in any response or log. Stored hashed in database | P1 | S | NFR-02 |
| TC-D-057 | Encrypted traffic | Capture traffic | HTTPS (TLS 1.2+) only | P1 | S | NFR-01 |
| TC-D-058 | Clear error messages | Trigger each delivery error | Message says what went wrong and what to do next | P2 | U | NFR-12 |

---

## Summary

| Area | Count |
| --- | --- |
| Login | 7 |
| Assigned orders | 10 |
| Mark as Delivered | 8 |
| Enter OTP | 12 |
| Resend OTP | 6 |
| Undelivered | 5 |
| Network and concurrency | 5 |
| Security and usability | 5 |
| **Total** | **58** |

## Points to confirm with BA before execution

| # | Test cases | Question |
| --- | --- | --- |
| Q1 | TC-D-043 | Are the 3 OTP attempts per order in total, or do they reset when the OTP is resent? |
| Q2 | TC-D-048 | How does the delivery boy close an order when the customer is unavailable or refuses (EX-15)? |
| Q3 | TC-D-042 | Does an older OTP stop working after a resend? |
| Q4 | TC-D-031 | Does a wrongly formatted OTP (e.g. 3 digits) use up an attempt? |
| Q5 | TC-D-029 vs TC-D-027 | BRD says a wrong OTP "keeps" the order Undelivered but also that Undelivered is final. Confirm the status shown between the 1st and 3rd wrong attempt. |
