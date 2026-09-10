import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import '../domain/location_model.dart';
import '../domain/location_categories.dart';

class LocationCard extends StatelessWidget {
  const LocationCard(
      {required this.location,
      required this.onTap,
      this.authorName,
      this.authorAvatarUrl,
      this.onAuthorTap,
      this.isSaved = false,
      this.onBookmarkTap,
      this.distanceMeters,
      this.compact = false,
      super.key});

  final LocationModel location;
  final VoidCallback onTap;
  final String? authorName;
  final String? authorAvatarUrl;
  final VoidCallback? onAuthorTap;
  final bool isSaved;
  final VoidCallback? onBookmarkTap;
  final double? distanceMeters;
  final bool compact;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          onTap: onTap,
          child: compact
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      width: 78,
                      height: 92,
                      child: LocationImage(
                          location: location, borderRadius: BorderRadius.zero)),
                  Expanded(child: _details(context, compactLayout: true)),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AspectRatio(
                      aspectRatio: 16 / 9,
                      child: LocationImage(
                          location: location, borderRadius: BorderRadius.zero)),
                  _details(context),
                  if (authorName != null) _author(),
                ]),
        ),
      );

  Widget _details(BuildContext context, {bool compactLayout = false}) =>
      Padding(
        padding: EdgeInsets.fromLTRB(
            compactLayout ? 9 : AppSpacing.lg,
            compactLayout ? 7 : AppSpacing.md,
            AppSpacing.xs,
            compactLayout ? 5 : AppSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(location.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: compactLayout ? 13 : null,
                        height: 1.12)),
                SizedBox(height: compactLayout ? 2 : AppSpacing.xs),
                Text(
                    location.description?.isNotEmpty == true
                        ? location.description!
                        : 'Відкрийте деталі цього місця',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: compactLayout
                        ? Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 11, height: 1.2)
                        : null),
                SizedBox(height: compactLayout ? 2 : AppSpacing.xs),
                Text(
                    '${locationCategoryPresentation(location.category).emoji} ${locationCategoryLabel(location.category)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary)),
                if (distanceMeters != null)
                  Text('${formatDistance(distanceMeters!)} від вас',
                      style: Theme.of(context).textTheme.labelSmall),
              ])),
          if (onBookmarkTap != null)
            IconButton(
                tooltip:
                    isSaved ? 'Прибрати зі збережених' : 'Зберегти локацію',
                onPressed: onBookmarkTap,
                visualDensity: VisualDensity.compact,
                icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border)),
        ]),
      );

  Widget _author() => InkWell(
        onTap: onAuthorTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
          child: Row(children: [
            CircleAvatar(
                radius: 16,
                backgroundImage: authorAvatarUrl?.isNotEmpty == true
                    ? NetworkImage(authorAvatarUrl!)
                    : null,
                child: authorAvatarUrl?.isNotEmpty == true
                    ? null
                    : const Icon(Icons.person, size: 18)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child: Text(authorName!,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.chevron_right, size: 18),
          ]),
        ),
      );

  static String formatDistance(double meters) => meters < 1000
      ? '${meters.round()} м'
      : '${(meters / 1000).toStringAsFixed(1)} км';
}

class LocationCategoryPresentation {
  const LocationCategoryPresentation(this.label, this.icon, this.emoji);
  final String label;
  final IconData icon;
  final String emoji;
}

final locationCategoryPresentations = <String, LocationCategoryPresentation>{
  for (final value in locationCategoryByKey.values)
    value.key: LocationCategoryPresentation(
      value.label,
      value.icon,
      switch (value.key) {
        'cafe' => '☕',
        'nature' => '🌲',
        'culture' => '🏛',
        'entertainment' => '🎭',
        'general' || 'all' => '✨',
        _ => '',
      },
    ),
};

LocationCategoryPresentation locationCategoryPresentation(String category) =>
    locationCategoryPresentations[category] ??
    locationCategoryPresentations['general']!;
String locationCategoryLabel(String category) =>
    locationCategoryPresentation(category).label;

class LocationImage extends StatelessWidget {
  const LocationImage(
      {required this.location,
      this.borderRadius = const BorderRadius.all(Radius.circular(16)),
      super.key});
  final LocationModel location;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final imageUrl = location.imageUrl?.trim();
    return ClipRRect(
      borderRadius: borderRadius,
      child: imageUrl?.isNotEmpty == true
          ? Image.network(imageUrl!,
              key: const Key('location_real_image'),
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder())
          : _placeholder(),
    );
  }

  Widget _placeholder() {
    final presentation = locationCategoryPresentation(location.category);
    return Container(
        key: const Key('location_image_placeholder'),
        color: const Color(0xFF183027),
        alignment: Alignment.center,
        child:
            Icon(presentation.icon, size: 38, color: const Color(0xFFD4A017)));
  }
}
