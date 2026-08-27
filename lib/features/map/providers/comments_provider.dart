import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/comment_model.dart';

class CommentsRepository {
  const CommentsRepository(this._supabase);

  final SupabaseClient _supabase;

  String get _currentUserId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw StateError('Користувач не авторизований.');
    return id;
  }

  Future<List<CommentModel>> fetchComments(String locationId) async {
    final rows = await _supabase
        .from('comments')
        .select(
          'id, location_id, author_id, body, rating, created_at, '
          'profiles!comments_author_id_fkey(display_name, username)',
        )
        .eq('location_id', locationId)
        .order('created_at', ascending: false)
        .limit(50);

    return rows
        .map((row) => CommentModel.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> addComment({
    required String locationId,
    required String text,
    int? rating,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty || normalizedText.length > 2000) {
      throw const FormatException(
          'Коментар має містити від 1 до 2000 символів.');
    }
    if (rating != null && (rating < 1 || rating > 5)) {
      throw const FormatException('Рейтинг має бути від 1 до 5.');
    }

    await _supabase.from('comments').insert({
      'location_id': locationId,
      'body': normalizedText,
      'rating': rating,
    });
  }

  Future<void> deleteOwnComment(String commentId) async {
    await _supabase
        .from('comments')
        .delete()
        .eq('id', commentId)
        .eq('author_id', _currentUserId);
  }
}

final commentsRepositoryProvider = Provider<CommentsRepository>((ref) {
  return CommentsRepository(Supabase.instance.client);
});

final commentsProvider = FutureProvider.autoDispose
    .family<List<CommentModel>, String>((ref, locationId) {
  return ref.watch(commentsRepositoryProvider).fetchComments(locationId);
});

class CommentsController {
  const CommentsController(this._ref);

  final Ref _ref;

  Future<void> addComment({
    required String locationId,
    required String text,
    int? rating,
  }) async {
    await _ref.read(commentsRepositoryProvider).addComment(
          locationId: locationId,
          text: text,
          rating: rating,
        );
    _ref.invalidate(commentsProvider(locationId));
  }

  Future<void> deleteOwnComment({
    required String locationId,
    required String commentId,
  }) async {
    await _ref.read(commentsRepositoryProvider).deleteOwnComment(commentId);
    _ref.invalidate(commentsProvider(locationId));
  }
}

final commentsControllerProvider = Provider<CommentsController>(
  CommentsController.new,
);
