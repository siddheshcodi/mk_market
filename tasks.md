# Tasks – Shared Platform (all modules)

| Item | Value |
| --- | --- |
| Product | MK Market – Product Ordering & Delivery Application |
| Source | `requirement.md` v1.2, module `spec.md` files |
| Date | 2026-10-08 |
| Module task files | `User/tasks.md`, `Store/tasks.md`, `Delivery Boy/tasks.md` |

These tasks are used by all three modules and must be done first. Module tasks refer to them by ID (for example `SH-05`).

**Estimates** are in person-days. **Owner:** BE = backend, FE = mobile, DO = DevOps, QA = testing, BA = business analyst.
**Status:** [x] done, [~] partly done (see backend/README.md "Not done yet"), [ ] not started.

---

## 1. Decisions needed before build

| ID | Task | Owner | Ref | Status |
| --- | --- | --- | --- | --- |
| SH-01 | Get BA / client sign-off on open items: Undelivered status during OTP retries, attempts reset on resend, customer unavailable (EX-15), out-of-stock orders (EX-10), session timeouts (NFR-06), OTP rate limit | BA | spec.md open items | [ ] |
| SH-02 | Confirm technology stack (mobile framework, backend, database, payment gateway, SMS provider, maps provider) | Architect | spec.md §3 | [ ] |
| SH-03 | Collect hardcoded store list (name, location), store manager numbers and delivery boy numbers from the client | BA | BR-04, A3, A15 | [ ] |

## 2. Project setup

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SH-04 | Repositories and branching | Mobile and backend repos, branch rules, code review rules | SH-02 | 0.5 | DO | – | [ ] |
| SH-05 | Environments | Dev, QA and production; HTTPS only (TLS 1.2+); secrets storage | SH-04 | 2 | DO | NFR-01 | [ ] |
| SH-06 | CI/CD | Build, test and deploy backend; Android and iOS builds for QA | SH-04 | 2 | DO | – | [ ] |
| SH-07 | Mobile app shell | One app for Android and iOS, navigation, role selection screen, API client, error message handling | SH-02 | 3 | FE | A13, NFR-12 | [ ] |
| SH-08 | Backend shell | API structure (`/api/v1`), standard error format, logging with personal data masked, health check | SH-02 | 2 | BE | NFR-12 | [x] |
| SH-09 | Monitoring and alerts | Uptime, error rate, SMS and payment failures | SH-05 | 1.5 | DO | NFR-10 | [ ] |

## 3. Database

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SH-10 | Core schema | `users`, `stores`, `store_managers`, `delivery_boys`, `products`, `orders`, `order_items`, `order_status_history`, `idempotency_keys`; money in paise | SH-08 | 2 | BE | spec.md §9 | [x] |
| SH-11 | Geo support | PostGIS, store location column and index | SH-10 | 0.5 | BE | BR-08 | [ ] |
| SH-12 | Hardcoded staff loading | `config/staff.yaml` loaded into stores, managers and delivery boys on each deploy; unique mobile numbers | SH-10, SH-03 | 1.5 | BE | FR-G-02, A15 | [x] |
| SH-13 | Product data load | Load existing products and prices (A2); search index on name | SH-10 | 1 | BE | A2, NFR-07 | [~] loader; client data pending |

## 4. Login and OTP (all roles)

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SH-14 | SMS provider integration | DLT templates for login OTP and delivery OTP, send queue with retry | SH-05 | 2 | BE | NFR-09, A9 | [~] code; DLT pending |
| SH-15 | Login OTP API | `POST /auth/otp/request`, `POST /auth/otp/verify`: 10-digit +91 check, 6-digit OTP, 5-min expiry, 30-s resend gap, hashed storage, single use, no account lock | SH-10, SH-14 | 3 | BE | BR-01 to BR-03, NFR-02 | [x] |
| SH-16 | Role check at login | `USER` open to all; `STORE_MANAGER` and `DELIVERY_BOY` only for hardcoded numbers, else "This number is not registered" with no SMS | SH-12, SH-15 | 1 | BE | BR-04, EX-04 | [x] |
| SH-17 | Tokens and sessions | Access + refresh tokens with role, staff and store IDs; logout; inactivity timeout | SH-15, SH-01 | 2 | BE | NFR-03, NFR-06 | [x] |
| SH-18 | Login screens | Mobile entry, OTP entry with 30-s countdown and resend, error messages | SH-07, SH-15 | 2.5 | FE | US-01, US-06 | [ ] |

## 5. Order status rules

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SH-19 | Order status service | Allowed changes only: Placed → On the way → Delivered / Undelivered; no going back or skipping; conditional updates so only the first of two actions wins; history record for every change | SH-10, SH-01 | 3 | BE | FR-G-01, BR-22, EX-18 | [x] |
| SH-20 | Role and ownership checks | Every API checks role and ownership (own orders / own store / assigned orders); 404 for others | SH-17 | 1.5 | BE | NFR-03 | [x] |
| SH-21 | Idempotency support | `Idempotency-Key` handling for payment confirm, assign and OTP verify | SH-10 | 1 | BE | NFR-11 | [x] |

## 6. Release

| ID | Task | Details | Depends on | Est. | Owner | Ref | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SH-22 | End-to-end testing across modules | Full order flow: login → search → pay → store assigns → delivery OTP → Delivered / Undelivered | All module tasks | 3 | QA | Section 5.1 | [ ] |
| SH-23 | Security review | HTTPS, OTP storage, role isolation, payment data, personal data in logs | All module tasks | 2 | BE / QA | NFR-01 to NFR-05 | [ ] |
| SH-24 | Production setup and store release | Production environment, SMS and payment live keys, Play Store and App Store submission | SH-22, SH-23 | 3 | DO / FE | – | [ ] |
| SH-25 | Client acceptance (UAT) | Client tests all three roles and signs off | SH-22 | 3 | BA / QA | – | [ ] |

## Summary

| Area | Est. (person-days) |
| --- | --- |
| Project setup | 11 |
| Database | 5 |
| Login and OTP | 10.5 |
| Order status rules | 5.5 |
| Release | 11 |
| **Total** | **43** |
