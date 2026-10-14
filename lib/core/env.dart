/// Server settings. Override at build time:
///   flutter run --dart-define=API_HOST=https://sdms-api.vercel.app
class Env {
  static const String apiHost = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'https://sdms-api.vercel.app',
  );

  /// Same public client key the web app sends (x-api-key).
  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: 'MEF-SecretKey@2026',
  );

  /// iOS push needs GoogleService-Info.plist and the Push capability in Xcode first:
  ///   flutter run --dart-define=PUSH_IOS=true
  /// (Android push is automatic once android/app/google-services.json exists.)
  static const bool pushIos = bool.fromEnvironment('PUSH_IOS');

  static const String apiBase = '$apiHost/api/admin';
}
