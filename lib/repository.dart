import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

// Jede Änderung speichert nur den betroffenen Fragebogen.
abstract class SessionRepository {
  Future<List<Session>> load();
  Future<void> save(Session session);
  Future<void> clear();
}

class LocalSessionRepository implements SessionRepository {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const _key = 'questionnaire.sessions.v1';
  @override
  Future<List<Session>> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded.map((entry) => Session.fromJson(
      Map<String, dynamic>.from(entry as Map))).toList();
  }
  @override
  Future<void> save(Session session) async {
    final sessions = await load();
    final index = sessions.indexWhere((entry) => entry.id == session.id);
    if (index < 0) { sessions.add(session); } else { sessions[index] = session; }
    await _preferences.setString(_key,
      jsonEncode(sessions.map((entry) => entry.toJson()).toList()));
  }
  @override
  Future<void> clear() => _preferences.remove(_key);
}


class SupabaseSessionRepository implements SessionRepository {
  final SupabaseClient client;
  SupabaseSessionRepository(this.client);

  Future<String> _userId() async {
    if (client.auth.currentSession?.isExpired ?? false) {
      await client.auth.refreshSession();
    }
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Anonyme Anmeldung fehlgeschlagen.');
    return user.id;
  }

  @override
  Future<List<Session>> load() async {
    final userId = await _userId();
    // PostgREST liefert paginiert; auch längere Verläufe vollständig laden.
    final sessions = <Session>[];
    const pageSize = 500;
    for (var offset = 0;; offset += pageSize) {
      final rows = await client.from('questionnaire_sessions').select()
        .eq('user_id', userId).order('started_at').order('id')
        .range(offset, offset + pageSize - 1);
      sessions.addAll(rows.map((row) => Session.fromJson({
        'id': row['id'], 'startedAt': row['started_at'],
        'completedAt': row['completed_at'], 'answers': row['answers'],
        'decision': row['decision'],
      })));
      if (rows.length < pageSize) break;
    }
    return sessions;
  }

  @override
  Future<void> save(Session session) async {
    final userId = await _userId();
    await client.from('questionnaire_sessions').upsert({
      'id': session.id, 'user_id': userId,
      'started_at': session.startedAt.toIso8601String(),
      'completed_at': session.completedAt?.toIso8601String(),
      'answers': session.answers, 'decision': session.decision?.toJson(),
    }, onConflict: 'user_id,id');
  }

  @override
  Future<void> clear() async {
    final userId = await _userId();
    await client.from('questionnaire_sessions').delete().eq('user_id', userId);
  }
}
