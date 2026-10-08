/// Build-time settings, passed with --dart-define.
///
///   flutter run -d chrome --web-port 8080
///   flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1   (Android emulator)
///   flutter build apk --dart-define=API_URL=https://api.example.com/api/v1 --dart-define=PAYMENT_MODE=razorpay
class AppConfig {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000/api/v1');

  /// "test" matches the backend's local mode (PAYMENT_PROVIDER=test): payments are Success / Fail buttons
  /// and OTPs are printed in the backend window. "razorpay" opens real Razorpay checkout (Android / iOS).
  static const paymentMode = String.fromEnvironment('PAYMENT_MODE', defaultValue: 'test');

  static bool get localMode => paymentMode == 'test';
}
