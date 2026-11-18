import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/theme/app_design.dart';
import '../domain/location_model.dart';
import 'location_card.dart';

/// A real location plus its distance from the user (when known).
class MapCarouselEntry {
  const MapCarouselEntry(this.location, this.distanceMeters);
  final LocationModel location;
  final double? distanceMeters;
}

/// The locations the carousel shows, nearest first. The carousel is only a
/// convenience strip over the map: every location stays on the map and in
/// search; [limit] merely bounds the strip (and the sort) to the nearest few
/// that are currently in view.
List<MapCarouselEntry> nearestCarouselEntries(
  List<LocationModel> locations, {
  double? userLatitude,
  double? userLongitude,
  int limit = 30,
}) {
  final hasUser = userLatitude != null && userLongitude != null;
  final entries = [
    for (final l in locations)
      MapCarouselEntry(
        l,
        hasUser
            ? Geolocator.distanceBetween(
                userLatitude, userLongitude, l.latitude, l.longitude)
            : null,
      ),
  ];
  if (hasUser) {
    entries.sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
  }
  return entries.length <= limit ? entries : entries.sublist(0, limit);
}

/// The rating text of a location, or `null` when there is no real rating
/// (absent or not a positive value): a missing rating is never shown as
/// "0.0".
String? carouselRatingLabel(double? rating) =>
    rating == null || !rating.isFinite || rating <= 0
        ? null
        : '${rating.toStringAsFixed(1)}/5';

/// Compact horizontal destination cards over the bottom of the map. Shows
/// only real data (photo, title, category, distance, rating) and never covers
/// more than a slim strip; the handle row collapses it entirely. The card of
/// [selectedId] (the last one opened) carries a thin gold outline.
class MapLocationCarousel extends StatelessWidget {
  const MapLocationCarousel({
    super.key,
    required this.entries,
    required this.expanded,
    required this.onToggle,
    required this.onSelected,
    this.selectedId,
  });

  static const double cardHeight = 88;
  static const double handleHeight = 26;

  /// Height the carousel occupies when expanded / collapsed (the map's
  /// floating buttons rise above it).
  static const double expandedHeight = handleHeight + cardHeight + 10;
  static const double collapsedHeight = handleHeight;

  final List<MapCarouselEntry> entries;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<LocationModel> onSelected;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: expanded ? 'Сховати список місць' : 'Показати список місць',
          child: InkWell(
            key: const Key('map_carousel_handle'),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            onTap: onToggle,
            child: Container(
              height: handleHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Поруч · ${entries.length}',
                      key: const Key('map_carousel_count'),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.textPrimary)),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          SizedBox(
            key: const Key('map_carousel'),
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) => _CarouselCard(
                entry: entries[index],
                selected: entries[index].location.id == selectedId,
                onTap: () => onSelected(entries[index].location),
              ),
            ),
          ),
          const SizedBox(height: 2),
        ],
      ],
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final MapCarouselEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = entry.location;
    final rating = carouselRatingLabel(location.rating);
    final distance = entry.distanceMeters == null
        ? null
        : LocationCard.formatDistance(entry.distanceMeters!);
    final category = locationCategoryPresentation(location.category);
    return SizedBox(
      width: 252,
      child: Material(
        key: Key('map_carousel_card_${location.id}'),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg + 2),
          // The thin gold outline marks the active card only.
          side: selected
              ? const BorderSide(color: AppColors.accent, width: 1)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                // The photo leads the card, inset with its own rounding.
                SizedBox(
                  width: 72,
                  height: double.infinity,
                  child: LocationImage(
                    location: location,
                    borderRadius: BorderRadius.circular(AppRadii.md + 2),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        location.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700, height: 1.15),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(category.icon,
                              size: 13, color: AppColors.accent),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              [category.label, if (distance != null) distance]
                                  .join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      if (rating != null) ...[
                        const SizedBox(height: 2),
                        Text(rating,
                            key: Key('map_carousel_rating_${location.id}'),
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom padding a map needs so Google's logo and attribution stay
/// visible above the carousel strip (used as `GoogleMap.padding`). Zero when
/// no carousel is shown.
double carouselMapBottomPadding({
  required bool shown,
  required bool expanded,
}) =>
    !shown
        ? 0
        : 8 +
            (expanded
                ? MapLocationCarousel.expandedHeight
                : MapLocationCarousel.collapsedHeight);
