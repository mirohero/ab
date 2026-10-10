import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

abstract class StudyRepository {
  Future<Map<String, dynamic>> call(String requestId, String action,
      {String? runId, String? questionId, String? optionId});
}

class StudyApiException implements Exception {
  final String code;
  final int retryAfter;
  StudyApiException(this.code, {this.retryAfter = 0});
  @override
  String toString() => code;
}

class SupabaseStudyRepository implements StudyRepository {
  final SupabaseClient client;
  DateTime? _blockedUntil;
  SupabaseStudyRepository(this.client);

  @override
  Future<Map<String, dynamic>> call(String requestId, String action,
      {String? runId, String? questionId, String? optionId}) async {
    final remaining = _blockedUntil?.difference(DateTime.now()).inSeconds ?? 0;
    if (remaining > 0) throw StudyApiException('RATE_LIMIT', retryAfter: remaining + 1);
    if (client.auth.currentSession?.isExpired ?? false) {
      await client.auth.refreshSession();
    }
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
    final raw = await client.rpc('study_call', params: {
      'p_request': requestId, 'p_action': action, 'p_run': runId,
      'p_question': questionId, 'p_option': optionId,
    });
    final response = Map<String, dynamic>.from(raw as Map);
    if (response['ok'] != true) {
      final code = response['error'] as String? ?? 'SERVER_ERROR';
      final retry = (response['retry_after'] as num?)?.toInt() ?? 0;
      if (retry > 0) _blockedUntil = DateTime.now().add(Duration(seconds: retry));
      throw StudyApiException(code, retryAfter: retry);
    }
    return Map<String, dynamic>.from(response['data'] as Map);
  }
}

class PendingRequest {
  final String id;
  final String action;
  final String? runId;
  final String? questionId;
  final String? optionId;
  PendingRequest(this.action, {this.runId, this.questionId, this.optionId})
      : id = const Uuid().v4();
}
