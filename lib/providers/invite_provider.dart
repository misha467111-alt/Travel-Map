import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final inviteServiceProvider = Provider<InviteService>((ref) => InviteService());

class InviteService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<String> generateInviteCode() async {
    if (_client.auth.currentUser == null) {
      throw StateError('Sign in is required.');
    }
    return _client.rpc<String>('create_invite');
  }

  Future<void> redeemCode(String code) async {
    if (_client.auth.currentUser == null) {
      throw StateError('Sign in is required.');
    }
    await _client.rpc<void>(
      'redeem_invite',
      params: {'p_code': code.trim().toUpperCase()},
    );
  }
}
