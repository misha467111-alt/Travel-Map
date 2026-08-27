import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'auth_state.g.dart';

@riverpod
Stream<Session?> authState(Ref ref) async* {
  final auth = Supabase.instance.client.auth;
  yield auth.currentSession;
  await for (final event in auth.onAuthStateChange) {
    yield event.session;
  }
}
