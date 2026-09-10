import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location_categories.dart';
import '../domain/location_query.dart';
import '../providers/locations_provider.dart';
import '../providers/map_filter_provider.dart';

class MapFiltersSheet extends ConsumerWidget {
  const MapFiltersSheet(
      {required this.bounds,
      required this.userLatitude,
      required this.userLongitude,
      super.key});

  final MapViewportBounds bounds;
  final double? userLatitude;
  final double? userLongitude;

  static const _gold = Color(0xFFD4A017);
  static const _background = Color(0xFF08110F);
  static const _card = Color(0xFF101A17);

  MapViewportQuery _query(MapFilterState value) => MapViewportQuery(
        bounds: bounds,
        category: value.category == 'all' ? null : value.category,
        userLatitude: userLatitude,
        userLongitude: userLongitude,
        maximumDistanceMeters:
            userLatitude == null ? null : value.maximumDistanceMeters,
        minimumRating: value.minimumRating,
        openNow: value.openNow,
        familyOnly: value.familyOnly,
        sort: value.rpcSort,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(mapFilterProvider).pending;
    final notifier = ref.read(mapFilterProvider.notifier);
    final count = ref.watch(filterCountProvider(_query(pending)));
    return Scaffold(
      key: const Key('map_filters_fullscreen'),
      backgroundColor: _background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 54,
        titleSpacing: 16,
        title: const Text('Фільтри',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            key: const Key('filters_close'),
            tooltip: 'Закрити',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Theme(
          data: Theme.of(context).copyWith(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
          ),
          child: Column(children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('Категорії'),
                    const SizedBox(height: 8),
                    GridView.builder(
                      key: const Key('map_filter_category_grid'),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisExtent: 64,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 7,
                      ),
                      itemCount: referenceLocationCategories.length,
                      itemBuilder: (context, index) {
                        final category = referenceLocationCategories[index];
                        final selected = pending.category == category.key;
                        return InkWell(
                          key: Key('filter_category_${category.key}'),
                          onTap: () => notifier.updatePending(
                              pending.copyWith(category: category.key)),
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            decoration: BoxDecoration(
                              color: selected
                                  ? category.referenceColor
                                      .withValues(alpha: .24)
                                  : _card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected
                                    ? category.referenceColor
                                    : const Color(0xFF273630),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(category.icon,
                                    size: 23, color: category.referenceColor),
                                const SizedBox(height: 3),
                                Text(category.label,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 9,
                                        height: 1.02,
                                        color: Color(0xFFF5F0E6))),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 13),
                    Row(children: [
                      const _Label('Відстань'),
                      const Spacer(),
                      Text(
                        const [
                          '1 км',
                          '10 км',
                          '50 км',
                          '100+ км'
                        ][pending.distanceIndex],
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ]),
                    SizedBox(
                      height: 30,
                      child: Slider(
                        key: const Key('filter_distance'),
                        value: pending.distanceIndex.toDouble(),
                        min: 0,
                        max: 3,
                        divisions: 3,
                        activeColor: _gold,
                        onChanged: userLatitude == null
                            ? null
                            : (value) => notifier.updatePending(
                                pending.copyWith(distanceIndex: value.round())),
                      ),
                    ),
                    const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('1 км', style: _scaleLabel),
                          Text('10 км', style: _scaleLabel),
                          Text('50 км', style: _scaleLabel),
                          Text('100+ км', style: _scaleLabel),
                        ]),
                    if (userLatitude == null)
                      const Text('Увімкніть геолокацію для фільтра відстані',
                          style: _scaleLabel),
                    const SizedBox(height: 12),
                    const _Label('Рейтинг'),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: Row(children: [
                        for (final option in const <(String, double?)>[
                          ('Будь-який', null),
                          ('4+', 4),
                          ('4.5+', 4.5),
                          ('5', 5),
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: _Choice(
                                label: option.$1,
                                selected: pending.minimumRating == option.$2,
                                onTap: () => notifier.updatePending(
                                  option.$2 == null
                                      ? pending.copyWith(clearRating: true)
                                      : pending.copyWith(
                                          minimumRating: option.$2),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    const _Label('Доступність'),
                    _SwitchRow(
                        label: 'Відкриті зараз',
                        value: pending.openNow,
                        onChanged: (value) => notifier
                            .updatePending(pending.copyWith(openNow: value))),
                    _SwitchRow(
                        label: 'Для дітей',
                        value: pending.familyOnly,
                        onChanged: (value) => notifier.updatePending(
                            pending.copyWith(familyOnly: value))),
                    Row(children: [
                      const _Label('Сортування'),
                      const Spacer(),
                      TextButton(
                          key: const Key('filters_reset'),
                          onPressed: notifier.resetPending,
                          child: const Text('Скинути')),
                    ]),
                    DropdownButtonFormField<LocationSort>(
                      key: const Key('filter_sort'),
                      initialValue: pending.sort,
                      decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9)),
                      items: [
                        const DropdownMenuItem(
                            value: LocationSort.newest,
                            child: Text('Нові спочатку')),
                        DropdownMenuItem(
                            value: LocationSort.nearest,
                            enabled: userLatitude != null,
                            child: const Text('Найближчі')),
                        const DropdownMenuItem(
                            value: LocationSort.rating,
                            child: Text('За рейтингом')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          notifier.updatePending(pending.copyWith(sort: value));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: _background,
                border: Border(top: BorderSide(color: Color(0xFF273630))),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    key: const Key('filters_apply'),
                    onPressed: count.isLoading
                        ? null
                        : () {
                            notifier.apply();
                            Navigator.pop(context);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold.withValues(alpha: .72),
                      foregroundColor: const Color(0xFF171106),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: count.when(
                      data: (value) => Text('Показати $value локацій'),
                      loading: () => const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (_, __) => const Text('Повторити підрахунок'),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  static const _scaleLabel = TextStyle(fontSize: 10, color: Colors.white54);
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600));
}

class _Choice extends StatelessWidget {
  const _Choice(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 32),
          backgroundColor:
              selected ? const Color(0x665A420D) : const Color(0xFF101A17),
          side: BorderSide(
              color:
                  selected ? const Color(0xFFD4A017) : const Color(0xFF273630)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10)),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 32,
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
          Transform.scale(
            scale: .82,
            alignment: Alignment.centerRight,
            child: Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: const Color(0xFFD4A017)),
          ),
        ]),
      );
}
