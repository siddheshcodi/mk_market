# Test Cases – User (Customer) Module

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Module | User (Customer) |
| Source | `requirement.md` v1.2 (BRD, 2026-10-07) |
| Prepared by | QA |
| Date | 2026-10-07 |

**Priority:** P1 = critical (blocks release), P2 = high, P3 = medium.
**Type:** F = functional, N = negative, B = boundary, S = security, P = performance, U = usability, I = integration.

---

## 1. Test data and environment

| Data | Value |
| --- | --- |
| Valid customer mobile | 9876543210 (new), 9123456780 (existing) |
| Login OTP | 6 digits, valid 5 minutes, resend after 30 seconds |
| Store A | Active store, 2.5 km by road from Address-1 |
| Store B | Active store, 3.8 km by road from Address-1 |
| Address-1 | Within 4 km by road of Store A and Store B |
| Address-2 | 3.5 km straight-line but 4.6 km by road from the nearest store |
| Address-3 | More than 10 km from every store |
| Payment | Gateway sandbox with UPI, card and net-banking test credentials |
| Products | "Milk 1L", "Milk 500ml", "Bread", "Rice 5kg" in the catalogue |

---

## 2. Login (FR-U-01, FR-U-02, US-01, BR-01 to BR-03, EX-01 to EX-03)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-U-001 | Login with a valid number and correct OTP | App installed, number not registered before | 1. Select Customer. 2. Enter 9876543210. 3. Tap Get OTP. 4. Enter the OTP received. 5. Submit | OTP SMS received. Customer logged in and lands on home/search screen. Account created | P1 | F | FR-U-01, FR-U-02, US-01 AC1–2 |
| TC-U-002 | Login with an existing customer number | Customer 9123456780 exists | Repeat TC-U-001 steps with 9123456780 | Logged in. Previous orders visible in My Orders | P1 | F | FR-U-02 |
| TC-U-003 | Mobile number with 9 digits | – | Enter 987654321, tap Get OTP | "Enter a valid 10-digit mobile number". No OTP sent | P1 | N/B | BR-01, EX-01 |
| TC-U-004 | Mobile number with 11 digits | – | Try to enter 98765432101 | Field accepts at most 10 digits, or shows the error. No OTP sent | P2 | B | BR-01 |
| TC-U-005 | Mobile number with letters or symbols | – | Enter 98765abc10 / 98765-4321 | Non-digits blocked or error shown. No OTP sent | P2 | N | BR-01 |
| TC-U-006 | Mobile number field empty | – | Tap Get OTP with empty field | Error "Enter a valid 10-digit mobile number". No OTP sent | P2 | N | BR-01 |
| TC-U-007 | Country code is +91 by default | – | Open the login screen | +91 shown and can't be changed to another country | P3 | F | BR-01, D8 |
| TC-U-008 | Wrong OTP | OTP requested | Enter a wrong 6-digit OTP, submit | Error shown. User stays on OTP screen and can retry or resend | P1 | N | US-01 AC3, EX-02 |
| TC-U-009 | No account lock after many wrong OTPs | OTP requested | 1. Enter wrong OTP 5 times. 2. Enter the correct OTP | Account not locked. Login succeeds with the correct OTP | P1 | N | BR-03, D9 |
| TC-U-010 | Expired OTP (after 5 minutes) | OTP requested | Wait 5 min 10 s, enter the received OTP | Error that the OTP expired. Resend available | P1 | B | BR-02, EX-02 |
| TC-U-011 | OTP used just before expiry | OTP requested | Enter the correct OTP at 4 min 50 s | Login succeeds | P2 | B | BR-02 |
| TC-U-012 | OTP length | OTP requested | Check the SMS and the input field | OTP is 6 digits. Field accepts only 6 digits | P2 | B | BR-02 |
| TC-U-013 | Resend not allowed before 30 seconds | OTP requested | Try tapping Resend immediately | Resend disabled with a countdown | P2 | B | EX-03 |
| TC-U-014 | Resend after 30 seconds | OTP requested | Wait 30 s, tap Resend, enter the new OTP | New OTP received. New OTP works | P1 | F | EX-03 |
| TC-U-015 | Old OTP after resend | Resent OTP | Enter the first (older) OTP | Rejected. Only the latest OTP works | P2 | S | BR-02 |
| TC-U-016 | OTP reused | Logged in once, then logged out | Enter the same OTP again | Rejected (single use) | P2 | S | NFR-02 |
| TC-U-017 | Login OTP SMS time | – | Request OTP 20 times, measure delivery time | At least 95% delivered within 30 seconds | P2 | P | NFR-09 |
| TC-U-018 | Logout | Logged in | Tap Logout | Back to login screen. Back button doesn't reopen customer screens | P2 | F/S | NFR-03 |
| TC-U-019 | Session expires after inactivity | Logged in | Leave the app inactive past the configured timeout, reopen | User asked to log in again (timeout value to be confirmed by client) | P3 | S | NFR-06 |

## 3. Product search (FR-U-03, FR-U-04, US-02, EX-05, A4)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-U-020 | Search by full product name | Logged in | Search "Bread" | "Bread" shown in results | P1 | F | FR-U-03, FR-U-04, US-02 AC1 |
| TC-U-021 | Search by part of a name | Logged in | Search "Milk" | "Milk 1L" and "Milk 500ml" shown | P1 | F | FR-U-04 |
| TC-U-022 | Search is not case sensitive | Logged in | Search "mILk" | Same results as "Milk" | P2 | F | FR-U-03 |
| TC-U-023 | No matching product | Logged in | Search "zzzz" | "No products found" | P1 | N | US-02 AC2, EX-05 |
| TC-U-024 | Search with spaces only / empty | Logged in | Search "   " | No search runs, or prompt to enter a product name. No crash | P3 | N | FR-U-03 |
| TC-U-025 | Search with special characters | Logged in | Search "%' OR 1=1 --" | "No products found". No error page, no data leak | P2 | S | NFR-03 |
| TC-U-026 | Search by category or brand only | Logged in | Search a category name that isn't in any product name | No category-based matches (search is by name only) | P3 | F | A4 |
| TC-U-027 | Result details | Logged in | Search "Rice" | Each result shows product name and price in INR | P2 | F | FR-U-04, A1 |
| TC-U-028 | Search response time | Normal load | Run 100 searches, measure | At least 95% return within 2 seconds | P2 | P | NFR-07 |

## 4. Selecting products (FR-U-05, BR-05)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-U-029 | Select one product | Search results shown | Add "Bread", proceed | Order shows 1 product. Proceed allowed | P1 | F | FR-U-05 |
| TC-U-030 | Select several products | Search results shown | Add "Bread" and "Milk 1L", proceed | Both products listed with correct total | P1 | F | FR-U-05 |
| TC-U-031 | Proceed with no product | Nothing selected | Try to proceed | Not allowed. Message asks to add at least one product | P1 | N/B | BR-05 |
| TC-U-032 | Remove the only product | One product selected | Remove it, try to proceed | Not allowed | P2 | N | BR-05 |
| TC-U-033 | Total amount is correct | Products selected | Check total | Total = sum of price × quantity. No delivery charge added | P1 | F | BR-23, A14 |
| TC-U-034 | No minimum order value | – | Select the cheapest single product, proceed | Allowed to proceed | P2 | B | BR-23, A14 |
| TC-U-035 | No coupons, offers or wishlist | – | Check search, product and order screens | No coupon, offer, wishlist, rating or review option | P3 | F | Out of scope |

## 5. Delivery address (FR-U-06, US-03 AC1, BR-06, BR-07, EX-06)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-U-036 | Valid full address | Products selected | Enter house no., street/area, city, 6-digit pincode of Address-1, continue | Moves to serviceability check and then payment | P1 | F | FR-U-06 |
| TC-U-037 | Pincode empty | Products selected | Fill all fields except pincode, continue | Blocked. Pincode highlighted | P1 | N | BR-07, EX-06, US-03 AC1 |
| TC-U-038 | Pincode with 5 digits | – | Enter 41100, continue | Blocked. Pincode error shown | P1 | B | BR-07 |
| TC-U-039 | Pincode with 7 digits | – | Try entering 4110381 | Only 6 digits accepted, or error shown | P2 | B | BR-07 |
| TC-U-040 | Pincode with letters | – | Enter 41A038 | Blocked. Pincode error shown | P2 | N | BR-07 |
| TC-U-041 | House / flat number empty | – | Leave it empty, continue | Blocked. Field highlighted | P1 | N | BR-07 |
| TC-U-042 | Street / area empty | – | Leave it empty, continue | Blocked. Field highlighted | P1 | N | BR-07 |
| TC-U-043 | City empty | – | Leave it empty, continue | Blocked. Field highlighted | P1 | N | BR-07 |
| TC-U-044 | Several fields empty | – | Leave house no., city and pincode empty, continue | All three fields highlighted at once | P2 | U | EX-06, NFR-12 |
| TC-U-045 | Skip address and go to payment | – | Try to reach the payment step without an address | Not possible | P1 | N | BR-06 |
| TC-U-046 | Only one address per order | – | Check address step | Only one delivery address can be set for the order | P3 | F | A5 |

## 6. Store within 4 km check (FR-U-07, FR-U-08, US-03 AC2–3, BR-08, BR-14, EX-07)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-U-047 | Store within 4 km by road | Address-1 | Enter Address-1, continue | Moves to payment | P1 | F | FR-U-07, US-03 AC2 |
| TC-U-048 | No store within 4 km | Address-3 | Enter Address-3, continue | "Currently no store is available in your area". Payment not offered | P1 | N | FR-U-08, US-03 AC3, EX-07 |
| TC-U-049 | Within 4 km straight-line but over 4 km by road | Address-2 | Enter Address-2, continue | "Currently no store is available in your area" (road distance is what counts) | P1 | B | D2, BR-08 |
| TC-U-050 | Store exactly at 4.0 km by road | Address with a store at 4.0 km road distance | Continue | Allowed to pay (4 km is within range) | P2 | B | BR-08 |
| TC-U-051 | Store at 4.1 km by road | Address with nearest store at 4.1 km | Continue | "Currently no store is available in your area" | P2 | B | BR-08 |
| TC-U-052 | Nearest store is chosen | Address-1 (Store A 2.5 km, Store B 3.8 km) | Place and pay for an order | Order goes only to Store A | P1 | I | BR-14, FR-S-02 |
| TC-U-053 | Message text | Address-3 | Check message | Text exactly "Currently no store is available in your area" | P2 | U | D3 |

## 7. Advance payment and order creation (FR-U-09 to FR-U-11, US-04, BR-09 to BR-11, EX-08, EX-09)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-U-054 | Successful UPI payment | Serviceable address | Pay full amount via UPI (sandbox success) | Order created with status "Placed". Confirmation with order ID shown | P1 | F | FR-U-10, FR-U-11, US-04 AC1 |
| TC-U-055 | Successful card payment | Serviceable address | Pay via debit/credit card | Order "Placed", order ID shown | P1 | F | BR-09 |
| TC-U-056 | Successful net banking payment | Serviceable address | Pay via net banking | Order "Placed", order ID shown | P1 | F | BR-09 |
| TC-U-057 | Full amount charged | Order total ₹250 | Pay | Gateway charges exactly ₹250, INR | P1 | F | FR-U-09, BR-09 |
| TC-U-058 | No pay-later or COD | – | Check payment screen | Only UPI, card, net banking. No COD or pay-later option | P1 | F | BR-09, Out of scope |
| TC-U-059 | Payment fails | Serviceable address | Use sandbox failure credentials | No order created. Failure message with Retry | P1 | N | BR-11, EX-08, US-04 AC2 |
| TC-U-060 | Payment cancelled by user | On gateway screen | Press back / cancel | No order created. Failure message with Retry | P1 | N | BR-11, EX-08 |
| TC-U-061 | Payment times out | On gateway screen | Leave it until the gateway times out | No order created | P2 | N | BR-11 |
| TC-U-062 | Retry after failure | TC-U-059 done | Tap Retry, pay successfully | Exactly one order created | P1 | F | EX-08 |
| TC-U-063 | Money debited, no gateway confirmation | Sandbox simulates missing confirmation | Pay | No order created. Message says refund will be handled manually | P1 | N | EX-09, BR-12 |
| TC-U-064 | Network lost after paying | – | Pay, switch off data before confirmation screen, switch on | Exactly one order (no duplicate, none lost). Order visible in My Orders | P1 | N | NFR-11 |
| TC-U-065 | Double tap on Pay | – | Tap Pay twice quickly | Only one payment and one order | P1 | N | NFR-11 |
| TC-U-066 | Order sent to store only after payment | Store manager logged in | Start payment, don't finish | Order doesn't appear in store's list | P1 | I | BR-10 |
| TC-U-067 | Order reaches store quickly | Store manager logged in | Complete payment, time it | Order appears in Store A's list within 10 seconds | P1 | P/I | NFR-08 |
| TC-U-068 | Card details not stored | – | Pay by card, inspect app storage and backend database | No card number or CVV stored by the app or backend | P1 | S | NFR-05 |
| TC-U-069 | Order ID is unique | Several orders placed | Compare order IDs | Each order has a different ID | P2 | F | FR-U-11 |

## 8. Order status (FR-U-12, FR-U-14, US-05, BR-13, BR-22, EX-16)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-U-070 | View my orders | Order placed | Open My Orders | Order listed with status "Placed" | P1 | F | FR-U-12, US-05 AC1 |
| TC-U-071 | Status updates to "On the way for delivery" | Order Placed | Store assigns a delivery boy, refresh My Orders | Status shows "On the way for delivery" | P1 | I | US-05 AC2 |
| TC-U-072 | Status updates to "Delivered" | Order on the way | Delivery boy enters correct OTP, refresh | Status shows "Delivered" | P1 | I | US-05 AC2 |
| TC-U-073 | Status updates to "Undelivered" | Order on the way | Delivery boy enters wrong OTP 3 times, refresh | Status shows "Undelivered" | P1 | I | FR-D-10 |
| TC-U-074 | No cancel option | Order in each status | Check list and detail screens | No cancel option for any status | P1 | N | FR-U-14, EX-16, US-05 AC3 |
| TC-U-075 | No push notification | Order status changes | Watch phone notifications | No push notification. Status only shown in app | P3 | F | A9 |
| TC-U-076 | Can't see other customers' orders | Two customers with orders | Customer 1 tries to open customer 2's order ID (e.g. via deep link or API) | Access denied / not found | P1 | S | NFR-03 |

## 9. Delivery OTP for the customer (FR-U-13, BR-18, BR-19)

| TC ID | Scenario | Preconditions | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TC-U-077 | Customer gets the delivery OTP | Order on the way | Delivery boy taps "Delivered" | Customer gets a 4-digit OTP SMS on the registered mobile number | P1 | I | FR-U-13, BR-18 |
| TC-U-078 | No OTP before "Delivered" tap | Order Placed / on the way | Check customer SMS | No delivery OTP received yet | P2 | N | BR-18 |
| TC-U-079 | OTP goes only to the registered number | Address has a different contact | Delivery boy taps "Delivered" | OTP sent only to the customer's login number | P1 | S | BR-18 |
| TC-U-080 | New OTP on resend | OTP sent | Delivery boy taps Resend | Customer gets a new 4-digit OTP | P2 | I | FR-D-09 |

## 10. Security and usability (NFR-01, NFR-03, NFR-12)

| TC ID | Scenario | Steps | Expected result | Priority | Type | Ref |
| --- | --- | --- | --- | --- | --- | --- |
| TC-U-081 | Encrypted traffic | Capture app traffic with a proxy | All calls use HTTPS (TLS 1.2+). Plain HTTP rejected | P1 | S | NFR-01 |
| TC-U-082 | Customer can't reach other modules | Logged in as customer, try store / delivery screens or APIs | Access denied | P1 | S | NFR-03 |
| TC-U-083 | Clear error messages | Trigger each error in this file | Each message says what went wrong and what to do next | P2 | U | NFR-12 |

---

## Summary

| Area | Count |
| --- | --- |
| Login | 19 |
| Product search | 9 |
| Selecting products | 7 |
| Delivery address | 11 |
| Store within 4 km | 7 |
| Payment and order | 16 |
| Order status | 7 |
| Delivery OTP | 4 |
| Security and usability | 3 |
| **Total** | **83** |
