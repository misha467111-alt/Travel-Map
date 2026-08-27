import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location_model.dart';
import '../providers/comments_provider.dart';
import '../providers/network_provider.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({required this.location, super.key});
  final LocationModel location;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _controller = TextEditingController();
  int? _rating;
  bool _submitting = false;
  String? _validationError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _validationError = 'Напишіть кілька слів про це місце');
      return;
    }
    if (_submitting || !ref.read(isOnlineProvider)) return;
    setState(() {
      _submitting = true;
      _validationError = null;
    });
    try {
      await ref.read(commentsControllerProvider).addComment(
            locationId: widget.location.id,
            text: text,
            rating: _rating,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не вдалося опублікувати відгук: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Новий відгук'),
          actions: [
            TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: const Text('Скасувати'),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.place_outlined)),
                  title: Text(widget.location.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(widget.location.category),
                ),
              ),
              const SizedBox(height: 22),
              Text('Ваша оцінка',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                children: List.generate(5, (index) {
                  final value = index + 1;
                  return IconButton(
                    tooltip: '$value з 5',
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _rating = value),
                    iconSize: 34,
                    icon: Icon(
                      value <= (_rating ?? 0) ? Icons.star : Icons.star_border,
                      color: const Color(0xFFD4A017),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                enabled: !_submitting,
                minLines: 6,
                maxLines: 10,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: 'Ваш відгук',
                  hintText: 'Розкажіть, що вам сподобалося…',
                  errorText: _validationError,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_outlined),
                label: const Text('Опублікувати'),
              ),
            ],
          ),
        ),
      );
}
