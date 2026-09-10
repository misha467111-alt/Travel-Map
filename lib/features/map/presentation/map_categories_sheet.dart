import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../domain/location_categories.dart';
import '../providers/map_filter_provider.dart';

Future<void> showMapCategoriesSheet({
  required BuildContext context,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => const MapCategoriesSheet(),
    );

class MapCategoriesSheet extends ConsumerWidget {
  const MapCategoriesSheet({super.key});

  static const _background = Color(0xFF0D1C17);
  static const _tileBackground = Color(0xFF10221B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(mapFilterProvider).applied.category;
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          key: const Key('map_categories_sheet'),
          color: _background,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            side: BorderSide(color: Color(0x334CAF50)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: (size.height * .53).clamp(390.0, 470.0),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Категорії',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFF5F0E6),
                                ),
                          ),
                        ),
                        IconButton(
                          key: const Key('close_map_categories'),
                          tooltip: 'Закрити',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        key: const Key('map_categories_grid'),
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 7,
                          crossAxisSpacing: 7,
                          childAspectRatio: textScale > 1.2 ? .82 : .9,
                        ),
                        itemCount: referenceLocationCategories.length,
                        itemBuilder: (context, index) {
                          final category = referenceLocationCategories[index];
                          final isSelected = selected == category.key;
                          return Semantics(
                            button: true,
                            selected: isSelected,
                            label: category.label.replaceAll('\n', ' '),
                            child: InkWell(
                              key: Key('map_category_${category.key}'),
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                              onTap: () => ref
                                  .read(mapFilterProvider.notifier)
                                  .selectCategory(category.key),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                curve: Curves.easeOut,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? category.referenceColor
                                          .withValues(alpha: .30)
                                      : _tileBackground,
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.sm),
                                  border: Border.all(
                                    color: isSelected
                                        ? category.referenceColor
                                        : const Color(0xFF294037),
                                  ),
                                  boxShadow: isSelected
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x33000000),
                                            blurRadius: 6,
                                            offset: Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      category.icon,
                                      size: 22,
                                      color: category.referenceColor,
                                    ),
                                    const SizedBox(height: 5),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      child: Text(
                                        category.label,
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          height: 1.05,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFFF5F0E6),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
