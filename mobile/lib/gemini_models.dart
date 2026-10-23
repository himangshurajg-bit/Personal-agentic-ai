/// Gemini API model IDs the app has verified against Google's current model docs.
/// Free-tier availability is account/project-dependent; this list is not a billing guarantee.
abstract final class GeminiModels {
  static const flashLiteFreeTier = 'gemini-3.5-flash-lite';
  static const flash25 = 'gemini-2.5-flash';
  static const flashLite25 = 'gemini-2.5-flash-lite';
  static const defaultModel = flashLiteFreeTier;
  static const modelsEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const supported = <String>[flashLiteFreeTier, flashLite25, flash25];
  static const labels = <String, String>{
    flashLiteFreeTier: 'Gemini 3.5 Flash-Lite · free tier available (default)',
    flashLite25: 'Gemini 2.5 Flash-Lite · free tier; 2.5 access restricted',
    flash25: 'Gemini 2.5 Flash · free tier; 2.5 access restricted',
  };

  static bool supports(String model) => supported.contains(model);
}
