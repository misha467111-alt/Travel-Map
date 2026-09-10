import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location_model.dart';
import '../providers/comments_provider.dart';
import '../providers/network_provider.dart';
import 'location_card.dart';

typedef ReviewSubmitter = Future<void> Function(String text, int? rating);

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({
    required this.location,
    this.submitter,
    this.isOnlineOverride,
    this.onSuccess,
    super.key,
  });
  final LocationModel location;
  final ReviewSubmitter? submitter;
  final bool? isOnlineOverride;
  final VoidCallback? onSuccess;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _controller = TextEditingController();
  int? _rating;
  bool _submitting = false;
  String? _validationError;
  String? _submitError;

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
    if (_submitting) return;
    final isOnline =
        (widget.isOnlineOverride ?? ref.read(isOnlineProvider)) == true;
    if (!isOnline) {
      setState(() => _submitError = 'Для публікації потрібен інтернет.');
      return;
    }
    setState(() {
      _submitting = true;
      _validationError = null;
      _submitError = null;
    });
    try {
      final submitter = widget.submitter ??
          (text, rating) => ref.read(commentsControllerProvider).addComment(
                locationId: widget.location.id,
                text: text,
                rating: rating,
              );
      await submitter(text, _rating);
      if (!mounted) return;
      if (widget.onSuccess != null) {
        widget.onSuccess!();
      } else {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _submitError = 'Не вдалося опублікувати відгук. Спробуйте ще раз.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final effectiveScale =
        mediaQuery.textScaler.scale(1).clamp(1.0, 1.12).toDouble();
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          title: const Text('Новий відгук',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              key: const Key('review_scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              children: [
                ReviewLocationSummary(location: widget.location),
                const SizedBox(height: 12),
                Text('Ваша оцінка',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                const SizedBox(height: 4),
                Semantics(
                  label: _rating == null
                      ? 'Оцінку не вибрано'
                      : 'Вибрана оцінка $_rating з 5',
                  liveRegion: true,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: constraints.maxWidth < 350 ? 0 : 4,
                    children: List.generate(5, (index) {
                      final value = index + 1;
                      final selected = value <= (_rating ?? 0);
                      return Semantics(
                        button: true,
                        selected: _rating == value,
                        label: 'Оцінка $value з 5',
                        child: IconButton(
                          key: Key('review_rating_$value'),
                          tooltip: '$value з 5',
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _rating = value),
                          constraints: const BoxConstraints(
                            minWidth: 38,
                            minHeight: 38,
                          ),
                          iconSize: constraints.maxWidth < 350 ? 26 : 28,
                          icon: Icon(
                            selected
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: selected
                                ? const Color(0xFFD4A017)
                                : Colors.white38,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('review_text_field'),
                  controller: _controller,
                  enabled: !_submitting,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) {
                    if (_validationError != null || _submitError != null) {
                      setState(() {
                        _validationError = null;
                        _submitError = null;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Поділіться враженнями...',
                    errorText: _validationError,
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: const Color(0xFF14231D),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: const BorderSide(color: Color(0xFFD4A017)),
                    ),
                  ),
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _submitError!,
                    key: const Key('review_submit_error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('review_submit_cta'),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox.square(
                          key: Key('review_submit_loading'),
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.publish_outlined),
                  label: const Text('Опублікувати'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReviewLocationSummary extends StatelessWidget {
  const ReviewLocationSummary({required this.location, super.key});
  final LocationModel location;

  @override
  Widget build(BuildContext context) {
    final category = locationCategoryPresentation(location.category);
    return Container(
      key: const Key('review_location_summary'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF14231D),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        SizedBox(
          width: 52,
          height: 52,
          child: LocationImage(
              location: location, borderRadius: BorderRadius.circular(9)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(location.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${category.emoji} ${category.label}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFD4A017),
                    )),
          ]),
        ),
      ]),
    );
  }
}
