import 'package:supabase_flutter/supabase_flutter.dart';

String localizedAuthError(Object error) {
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login') ||
        message.contains('invalid credentials')) {
      return 'Невірний email або пароль.';
    }
    if (message.contains('already registered') ||
        message.contains('already exists')) {
      return 'Користувач із таким email вже існує.';
    }
    if (message.contains('password')) {
      return 'Пароль має містити щонайменше 6 символів.';
    }
    if (message.contains('email not confirmed')) {
      return 'Підтвердьте email перед входом.';
    }
    return error.message;
  }
  return 'Не вдалося виконати запит. Перевірте інтернет і спробуйте ще раз.';
}
