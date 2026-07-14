/// On-prem / HKU IT LLM (OpenAI-compatible chat completions).
///
/// **HKU Vertex AI (recommended):**
/// ```bash
/// # scripts/local_llm.env
/// LOCAL_LLM_BASE_URL=https://api.hku.hk/vertexai
/// LOCAL_LLM_MODEL=qwen/qwen3-next-80b-a3b-instruct-maas
/// LOCAL_LLM_AUTH=apim
/// ```
/// Put the IT **primary** subscription key in `secrets/internal_llm_api_key.txt`
/// (gitignored). Secondary key is for rotation only.
///
/// Build via `scripts/run_offline_dev.sh` or:
/// ```bash
/// --dart-define=LOCAL_LLM_BASE_URL=https://api.hku.hk/vertexai
/// --dart-define=LOCAL_LLM_MODEL=qwen/qwen3-next-80b-a3b-instruct-maas
/// --dart-define=LOCAL_LLM_API_KEY=your-primary-key
/// --dart-define=LOCAL_LLM_AUTH=apim
/// ```
class LocalLlmConfig {
  LocalLlmConfig._();

  static const String baseUrlOverride = String.fromEnvironment(
    'LOCAL_LLM_BASE_URL',
    defaultValue: '',
  );

  static const String apiKey = String.fromEnvironment(
    'LOCAL_LLM_API_KEY',
    defaultValue: '',
  );

  static const String model = String.fromEnvironment(
    'LOCAL_LLM_MODEL',
    defaultValue: '',
  );

  /// `apim` = HKU `api-key` header (api.hku.hk Vertex AI gateway).
  /// `bearer` = `Authorization: Bearer …` (Ollama / some OpenAI gateways).
  /// `auto` = apim when base URL contains `api.hku.hk`, else bearer.
  static const String authMode = String.fromEnvironment(
    'LOCAL_LLM_AUTH',
    defaultValue: 'auto',
  );

  static String get baseUrl =>
      baseUrlOverride.trim().replaceAll(RegExp(r'/+$'), '');

  static bool get useLocalLlm => baseUrl.isNotEmpty;

  static bool get isConfigured =>
      useLocalLlm && apiKey.trim().isNotEmpty && model.trim().isNotEmpty;

  static String get chatCompletionsUrl => '$baseUrl/chat/completions';

  static bool get usesApimSubscriptionKey {
    final mode = authMode.trim().toLowerCase();
    if (mode == 'apim' || mode == 'subscription') return true;
    if (mode == 'bearer') return false;
    return baseUrl.toLowerCase().contains('api.hku.hk');
  }

  static Map<String, String> authorizationHeaders() {
    final key = apiKey.trim();
    if (key.isEmpty) return const {};
    if (usesApimSubscriptionKey) {
      // HKU IT Vertex AI gateway expects `api-key`, not Azure APIM's
      // Ocp-Apim-Subscription-Key (that header returns 401 on api.hku.hk).
      return {'api-key': key};
    }
    return {'Authorization': 'Bearer $key'};
  }
}
