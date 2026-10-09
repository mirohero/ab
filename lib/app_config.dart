class AppConfig {
  static const storageMode = String.fromEnvironment('STORAGE_MODE', defaultValue: 'supabase');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static void validate() {
    if (storageMode == 'local') return;
    if (storageMode != 'supabase') {
      throw StateError('STORAGE_MODE muss local oder supabase sein.');
    }
    final url = Uri.tryParse(supabaseUrl);
    if (url == null || url.scheme != 'https' || url.host.isEmpty || supabaseKey.isEmpty) {
      throw StateError('Bitte SUPABASE_URL und SUPABASE_PUBLISHABLE_KEY in config/app_config.json eintragen und mit --dart-define-from-file=config/app_config.json starten.');
    }
    if (supabaseKey.startsWith('sb_secret_')) {
      throw StateError('Verwende einen öffentlichen Publishable Key, keinen Secret Key.');
    }
  }
}
