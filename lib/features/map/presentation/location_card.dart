import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import '../domain/location_model.dart';

class LocationCard extends StatelessWidget {
  const LocationCard({
    required this.location,
    required this.onTap,
    this.authorName,
    this.authorAvatarUrl,
    this.onAuthorTap,
    this.isSaved = false,
    this.onBookmarkTap,
    this.distanceMeters,
    this.compact = false,
    super.key,
  });

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
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact && location.imageUrl != null)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    location.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            location.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            location.description?.isNotEmpty == true
                                ? location.description!
                                : 'Відкрийте деталі цього місця',
                            maxLines: compact ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            locationCategoryLabel(location.category),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                          if (distanceMeters != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${formatDistance(distanceMeters!)} від вас',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onBookmarkTap != null)
                      IconButton(
                        tooltip: isSaved
                            ? 'Прибрати зі збережених'
                            : 'Зберегти локацію',
                        onPressed: onBookmarkTap,
                        icon: Icon(
                          isSaved ? Icons.bookmark : Icons.bookmark_border,
                        ),
                      ),
                  ],
                ),
              ),
              if (authorName != null)
                InkWell(
                  onTap: onAuthorTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: authorAvatarUrl?.isNotEmpty == true
                              ? NetworkImage(authorAvatarUrl!)
                              : null,
                          child: authorAvatarUrl?.isNotEmpty == true
                              ? null
                              : const Icon(Icons.person, size: 18),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            authorName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  static String formatDistance(double meters) => meters < 1000
      ? '${meters.round()} м'
      : '${(meters / 1000).toStringAsFixed(1)} км';
}

String locationCategoryLabel(String category) => switch (category) {
      'cafe' => 'Кафе',
      'nature' => 'Природа',
      'culture' => 'Культура',
      'entertainment' => 'Розваги',
      _ => 'Локація',
    };
