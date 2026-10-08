# Tasks – Delivery Boy Module

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Module | Delivery Boy |
| Source | `requirement.md` v1.2, `spec.md`, `plan.md`, `testcases.md` |
| Date | 2026-10-08 |
| Shared tasks | `../tasks.md` (IDs starting `SH-`) |

**Estimates** are in person-days. **Owner:** BE = backend, FE = mobile, QA = testing.
**Status:** [x] done, [~] partly done (see backend/README.md "Not done yet"), [ ] not started.

---

## 1. Login

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D-01 | Delivery boy login flow | Shared login screens with role `DELIVERY_BOY`; only hardcoded numbers; token carries staff and store IDs | SH-12, SH-16, SH-18 | 1 | FE / BE | FR-D-01, US-06, BR-04 | [~] backend |

## 2. Assigned orders

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D-02 | Assigned orders API | `GET /delivery/orders` (Active, Completed) and `GET /delivery/orders/{id}`; only orders assigned to this delivery boy; customer name, mobile and address only while "On the way" | SH-19, SH-20, S-08 | 2 | BE | FR-D-02, FR-D-03, BR-17, NFR-04 | [x] |
| D-03 | Orders list screen | Active and Completed tabs; refresh every 10 s on screen, pull to refresh; "OTP sent" badge | D-02, SH-07 | 2 | FE | FR-D-02, US-09 | [ ] |
| D-04 | Order details screen | Customer name, tap to call, full address, open in phone maps, items, "Paid in advance – do not collect money"; no caching of customer details; block screenshots on Android | D-02 | 2 | FE | FR-D-03, NFR-04 | [ ] |

## 3. Delivery OTP

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D-05 | Send delivery OTP API | `POST /delivery/orders/{id}/delivery-otp`: check order is assigned and "On the way"; create 4-digit OTP, store hashed, valid 10 min; SMS to customer's registered number only; never return the OTP; no duplicate SMS on double tap | SH-14, U-17, D-02 | 2 | BE | FR-D-04, FR-D-05, BR-18, BR-19, NFR-02 | [~] code; DLT template pending |
| D-06 | Resend OTP API | `POST .../delivery-otp/resend`: new OTP, old one stops working, up to 2 resends, 30 s apart | D-05 | 1 | BE | FR-D-09, EX-14 | [x] |
| D-07 | Verify OTP API | `POST .../delivery-otp/verify`: correct OTP sets "Delivered"; wrong OTP shows attempts left; expired OTP rejected; safe on retry; counter locked so parallel calls can't exceed limits | D-05, SH-21 | 2.5 | BE | FR-D-06, FR-D-07, FR-D-08, BR-20, EX-17 | [x] |
| D-08 | Undelivered after 3 wrong OTPs | On 3rd wrong attempt set "Undelivered" with reason; order shows in store's Returned tab | D-07, SH-19 | 1 | BE | FR-D-10, BR-21, D6 | [x] |
| D-09 | Delivered and OTP screens | Confirm dialog on "Delivered"; 4-digit entry; attempts left, resends left, expiry countdown; resend button; success and failure screens; "Checking…" while waiting for server | D-05, D-06, D-07 | 3 | FE | US-10, US-11, NFR-12 | [ ] |
| D-10 | Recover after network loss or app close | Retry with same key after network loss; on reopen, reload order and OTP state | D-09 | 1 | FE | EX-17, NFR-11 | [ ] |
| D-11 | Customer unavailable / refuses (pending decision) | Only if BA approves (SH-01): "Return to store" action that sets "Undelivered" with a reason | SH-01, D-08 | 1.5 | BE / FE | EX-15 | [ ] waiting for BA (SH-01) |

## 4. Testing

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D-12 | Unit and API tests | Only assigned orders, OTP hashing, 3 attempts, 2 resends, 10-min expiry, single use, parallel verify calls, OTP never in responses or logs | D-02 to D-08 | 2.5 | BE | – | [x] |
| D-13 | Test data setup | Delivery boys for two stores, customer phones with real SIMs, at least 10 assigned orders per test run | SH-12 | 1 | QA | plan.md §7.2 | [ ] |
| D-14 | Run test cases | Run the 58 cases in `testcases.md`, log defects, retest | All above | 12 | QA | plan.md §7 | [ ] |
| D-15 | SMS speed and security check | OTP SMS under 30 s (NFR-09); check database and logs for plain-text OTPs; customer details removed from phone after delivery | D-14 | 1.5 | QA | NFR-02, NFR-04, NFR-09 | [ ] |

## Summary

| Area | Est. (person-days) |
| --- | --- |
| Login | 1 |
| Assigned orders | 6 |
| Delivery OTP | 12 (incl. 1.5 pending decision) |
| Testing | 17 |
| **Total** | **36** |

## Order of work

1. D-01 can start once shared login (SH-16) is done.
2. D-02 needs the dispatch API from the Store module (S-08).
3. D-05 → D-06 → D-07 → D-08 in that order; D-09 can start in parallel using the agreed API format.
4. D-11 starts only after BA confirms EX-15 handling.
