# Implementation Plan – Delivery Boy Module

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Module | Delivery Boy |
| Inputs | `requirement.md` v1.2, `spec.md` (what to build) |
| Outputs | `tasks.md` (work items), `testcases.md` (tests) |
| Date | 2026-10-08 |
| Status | Draft – stack choice and open items pending (`../tasks.md` SH-01, SH-02) |

---

## 1. Summary

Build the delivery boy side of the app. The delivery boy logs in with a hardcoded number and sees only the orders assigned to them, with the customer's name, mobile number and address. Tapping "Delivered" sends a 4-digit OTP to the customer. The order closes as Delivered only when the correct OTP is entered. After 3 wrong OTPs it becomes Undelivered and goes back to the store.

## 2. Technical choices

Uses the same stack as the rest of the app (`../User/plan.md` §2). Specific to this module:

| Area | Choice | Why |
| --- | --- | --- |
| Delivery OTP | Separate from login OTP: 4 digits, 10 min, 3 attempts, 2 resends, linked to one order | BR-19, A10 |
| OTP storage | HMAC-SHA256 with a server secret, salted with the order ID; never returned by any API | NFR-02 |
| Attempt counting | Row lock on the order's OTP counter, so parallel calls can't go over 3 attempts | BR-19 |
| Network safety | `Idempotency-Key` on OTP verify; the app retries with the same key | EX-17, NFR-11 |
| Order refresh | Polling every 10 s while the list is open | A9 (no push) |
| Customer data on phone | Not saved on the device; cleared on logout or order close; screenshots blocked on Android | NFR-04 |

## 3. Code structure

```text
mobile/lib/features/delivery/
  orders/                   # D-03, D-04
  otp/                      # D-09, D-10

backend/src/
  delivery-orders/          # assigned orders APIs (D-02)
  delivery-otp/             # send, resend, verify, undelivered (D-05 to D-08)
  orders/                   # shared order status rules (SH-19)
```

## 4. Key implementation decisions

| # | Decision | Detail | Ref |
| --- | --- | --- | --- |
| 1 | Undelivered only after the 3rd wrong OTP | During attempts the order stays "On the way" with an active OTP. It becomes final "Undelivered" on the 3rd wrong attempt. Needs BA sign-off (SH-01) | FR-D-08, §5.2 |
| 2 | 3 attempts per order | A resend gives a new code but doesn't reset attempts. Needs BA sign-off | BR-19 |
| 3 | One active OTP per order | A resend cancels the old OTP | BR-19 |
| 4 | Expired OTP doesn't use an attempt | The delivery boy is asked to resend | BR-19 |
| 5 | Repeat "Delivered" taps don't send a new SMS | The existing OTP state is returned. New codes come only from resend | NFR-11 |
| 6 | Customer details only while "On the way" | After Delivered or Undelivered, the API returns no name, mobile or address | NFR-04 |
| 7 | OTP SMS only to the customer's login number | Never to the address contact | BR-18 |
| 8 | "Return to store" action is on hold | Built only if the BA approves the EX-15 handling (D-11) | EX-15 |

Full API and OTP rules are in `spec.md` §7–§8.

## 5. Dependencies

| Depends on | Needed for | Task |
| --- | --- | --- |
| Delivery boy numbers from the client | Login | SH-03, SH-12 |
| Shared login and role check | Login | SH-16 |
| Dispatch from the Store module | Assigned orders | S-08 |
| SMS provider with DLT delivery OTP template | Sending OTP | SH-14, U-17 |
| Order status rules | Delivered and Undelivered | SH-19 |
| BA answers (Undelivered status, attempts on resend, EX-15) | OTP logic, D-11 | SH-01 |
| **Used by** Store module | Returned tab | D-08 → S-10 |
| **Used by** User module | Status shown to the customer | D-07 |

## 6. Phases and milestones

Assumed team: shares the backend and mobile developers with the other modules; 1 QA from phase 3. Weeks are counted after shared setup.

| Phase | Weeks | Tasks | Milestone (done when) |
| --- | --- | --- | --- |
| 1. Login and assigned orders | 3–4 | D-01, D-02, D-03, D-04 | Delivery boy sees only their assigned orders with customer details |
| 2. Delivery OTP | 4–6 | D-05 to D-10 | Correct OTP gives Delivered, 3 wrong give Undelivered, resend limit works, safe on network loss |
| 3. Pending decision | 6 | D-11 | Built or dropped depending on the BA's answer |
| 4. Testing and fixes | 6–8 | D-12 to D-15 | Exit criteria in §7.3 met |

## 7. Testing approach

### 7.1 Levels

| Level | Who | What |
| --- | --- | --- |
| Unit | Developers | OTP hashing, limits, expiry, single use, status changes |
| API | Developers / QA | Other delivery boys' orders rejected; OTP never in responses; limits enforced with parallel calls |
| Functional | QA | The 58 cases in `testcases.md` |
| End-to-end | QA | Store assigns → delivery boy taps Delivered → customer receives OTP → Delivered / Undelivered shown in all three modules |
| Security | QA | OTP not in database as plain text or in logs; customer details removed from the phone after close |
| Performance | QA | OTP SMS under 30 s (NFR-09) |

### 7.2 Test data

| Data | Details |
| --- | --- |
| Delivery boys | DB-A1, DB-A2 (Store A), DB-B1 (Store B), hardcoded |
| Customers | Two customers with real SIMs; one with a different contact number in the address |
| Orders | At least 10 assigned orders per test run. Each failed-delivery test uses up one order |
| Devices | Android 10 (budget phone), Android 13, Android 15, iOS 18+; 4G, slow 3G, airplane mode |

A QA-only setting to shorten the 10-minute expiry will speed up testing. At least one run must still use the real 10 minutes.

### 7.3 Entry and exit

- **Start testing when:** delivery boy numbers are in the QA build, the Store module can dispatch orders, customer phones receive the OTP SMS, and BA answers for SH-01 are available.
- **Done when:**
  - all P1 cases pass and at least 95% of P2 cases have been run
  - no Critical or High defects are open
  - the OTP is never visible to the delivery boy
  - the attempt and resend limits are proven on the server
  - NFR-09 is met

## 8. Risks

| # | Risk | Mitigation |
| --- | --- | --- |
| R1 | BA answers on Undelivered status and attempts arrive late | Build to the proposed rules; keep limits and behaviour in config |
| R2 | No way to close an order when the customer is unavailable (EX-15) | D-11 ready to build once approved |
| R3 | SMS delays from the operator | Second SMS route as fallback; clear "couldn't send" message with retry |
| R4 | Testing blocked if Store dispatch is broken | Test API to create assigned orders in QA only |
| R5 | Long 10-minute expiry tests | QA-only shorter expiry setting |

## 9. Definition of done (per task)

- Code reviewed and merged, and unit tests pass
- No OTP value in any API response, log or analytics event
- Every query is limited to the delivery boy's own assigned orders
- Works on a budget Android phone and one iOS device
- Related test cases in `testcases.md` pass in the QA environment
