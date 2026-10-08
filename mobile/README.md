# MK Market – Mobile app

One Flutter app for Android, iOS and web with a separate view for each role after login (A13):
**Customer**, **Store manager** and **Delivery boy**. Talks to the backend in `../backend`.

## Run locally

```bash
# 1. Backend with no outside services (in-memory DB, OTPs printed in its window, test payments)
cd ../backend && npm install && npm run local

# 2. App
flutter pub get
flutter run -d chrome --web-port 8080                              # web
flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1      # Android emulator
```

Release build: `--dart-define=API_URL=https://… --dart-define=PAYMENT_MODE=razorpay`.

## Tests

```bash
flutter analyze
flutter test
```

Widget tests cover login with OTP, search → address → payment → order ID, the 4 km no-store block,
unregistered staff numbers, the store's one-step assign, the customer's share-OTP prompt with no cancel
option, and delivery OTP attempts.

## Code layout

```text
lib/
  core/       theme (design tokens, light + dark), shared widgets, API client, session, formatting, order status
  auth/       role picker, mobile number, OTP boxes
  customer/   home (Shop / My orders), search grid + cart bar, address, payment, confirmation, tracking
  store/      inbox tabs with counts, order details with packing list, assign sheet
  delivery/   assigned orders, order details (call / maps), delivery OTP entry and result
```

## UX notes

- One design system (`core/theme.dart`): green brand, 16 px radii, status colours used the same way in all roles.
- Every list has a loading skeleton, an empty state with next steps, and an offline/error state with "Try again".
- No push notifications (A9): lists and tracking screens refresh on a timer and support pull-to-refresh.
- Customer: popular and recent searches, Add → stepper (1–10), floating cart bar, 3-step checkout header,
  "price held" countdown, a "what happens next" explainer, and an active-order card on the home screen.
- Store: waiting-time badge that turns amber after 10 min and red after 30, "Assign" right on the card,
  vibration + sound + highlight for new orders, a "Least busy" hint when choosing a delivery boy.
- Delivery: "Paid in advance – do not collect money" banner, big Call / Open in Maps buttons, a handover
  checklist, and an OTP screen showing attempts left, resends left and expiry time. It never auto-submits, so a typo doesn't use up an attempt.
