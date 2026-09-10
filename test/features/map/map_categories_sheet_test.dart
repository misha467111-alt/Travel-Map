import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_categories.dart';
import 'package:flutter_application_1/features/map/presentation/map_categories_sheet.dart';
import 'package:flutter_application_1/features/map/providers/map_filter_provider.dart';

void main() {
  testWidgets('shows all canonical reference categories without legacy general',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(412, 915)),
            child: Scaffold(body: MapCategoriesSheet()),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('map_categories_grid')), findsOneWidget);
    for (final category in referenceLocationCategories) {
      expect(find.byKey(Key('map_category_${category.key}')), findsOneWidget);
    }
    expect(find.byKey(const Key('map_category_general')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection uses and immediately updates the shared filter state',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(mapFilterProvider.notifier).selectCategory('historic');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(412, 915)),
            child: Scaffold(body: MapCategoriesSheet()),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.byKey(const Key('map_category_historic')),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('map_category_kids')));
    await tester.pumpAndSettle();
    expect(container.read(mapFilterProvider).applied.category, 'kids');
    expect(container.read(mapFilterProvider).pending.category, 'kids');

    await tester.tap(find.byKey(const Key('map_category_all')));
    await tester.pumpAndSettle();
    expect(container.read(mapFilterProvider).applied.category, 'all');
  });
}
