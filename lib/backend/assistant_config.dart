/// Gemini key for the system support assistant only. Never show this in the UI.
/// Pass at build time: `--dart-define=PHYIMACY_GEMINI_KEY=...`
class AssistantConfig {
  static const geminiKey = String.fromEnvironment('PHYIMACY_GEMINI_KEY');
  static const model = 'gemini-2.0-flash';
  static const fallbackModel = 'gemini-1.5-flash';

  static bool get hasGeminiKey => geminiKey.trim().isNotEmpty;
}
