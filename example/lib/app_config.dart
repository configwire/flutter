// ---------------------------------------------------------------------------
// ⚙️  Configuration — replace with your real values.
// ---------------------------------------------------------------------------

/// Example connection + flag configuration. To point at a real ConfigWire
/// server, edit these constants (or the dashboard flag keys below).
abstract final class AppConfig {
  static const baseUrl = 'http://localhost:8090'; // ConfigWire server base URL
  static const apiKey = 'YOUR_SDK_KEY'; // SDK key (X-ConfigWire-Key header)

  // Flag keys used in this example (define them in your ConfigWire dashboard).
  static const welcomeFlag = 'welcome_message'; // String flag
  static const newCheckoutFlag = 'new_checkout'; // Bool flag

  // In-app defaults — served immediately before the first successful fetch.
  static const defaults = <String, Object?>{
    welcomeFlag: 'Hello from ConfigWire! 👋',
    newCheckoutFlag: false,
  };
}
