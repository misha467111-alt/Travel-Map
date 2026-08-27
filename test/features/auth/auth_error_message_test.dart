import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_application_1/features/auth/presentation/auth_error_message.dart';

void main() {
  test('localizes invalid credentials', () {
    expect(
      localizedAuthError(const AuthException('Invalid login credentials')),
      'Невірний email або пароль.',
    );
  });

  test('localizes duplicate account', () {
    expect(
      localizedAuthError(const AuthException('User already registered')),
      'Користувач із таким email вже існує.',
    );
  });
}
