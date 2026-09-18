import 'package:shared_preferences/shared_preferences.dart';

import 'opencode_server.dart';

/// Настройки подключения к AI-серверу (opencode serve в Termux).
class AiSettings {
  AiSettings({required this.baseUrl, required this.agent});

  static const String _kBaseUrl = 'ai_base_url';
  static const String _kAgent = 'ai_agent';

  final String baseUrl;
  final String agent;

  static const AiSettings defaults = AiSettings(
    baseUrl: OpenCodeServer.defaultBaseUrl,
    agent: 'tutor',
  );

  static Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AiSettings(
      baseUrl: prefs.getString(_kBaseUrl) ?? defaults.baseUrl,
      agent: prefs.getString(_kAgent) ?? defaults.agent,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, baseUrl);
    await prefs.setString(_kAgent, agent);
  }

  AiSettings copyWith({String? baseUrl, String? agent}) => AiSettings(
    baseUrl: baseUrl ?? this.baseUrl,
    agent: agent ?? this.agent,
  );
}