import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/domain/route.dart';
import 'package:flutter_application_1/features/map/presentation/route_details_screen.dart';
import 'package:flutter_application_1/features/map/presentation/routes_presentation.dart';
import 'package:flutter_application_1/features/map/providers/route_provider.dart';

void main() {
  final destination = LocationModel(
    id: 'destination-1',
    userId: 'user-1',
    title: 'Дуже довга назва канонічної кінцевої локації маршруту',
    description: 'Опис локації, а не вигаданий опис маршруту.',
    category: 'nature',
    latitude: 50.46,
    longitude: 30.52,
    createdAt: DateTime.utc(2026),
  );
  const activeRoute = RouteState(
    status: RouteStatus.success,
    start: RoutePoint(latitude: 50.45, longitude: 30.51),
    end: RoutePoint(latitude: 50.46, longitude: 30.52),
    points: [
      RoutePoint(latitude: 50.45, longitude: 30.51),
      RoutePoint(latitude: 50.455, longitude: 30.515),
      RoutePoint(latitude: 50.46, longitude: 30.52),
    ],
    distanceMeters: 12400,
    durationSeconds: 1680,
  );

  testWidgets('routes header, no-active state and create CTA are functional',
      (tester) async {
    var created = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Маршрути')),
        body: RoutesContent(
          route: const RouteState(),
          destination: null,
          onCreateRoute: () => created++,
        ),
      ),
    ));

    expect(find.text('Маршрути'), findsOneWidget);
    expect(find.text('АКТИВНИЙ МАРШРУТ'), findsOneWidget);
    expect(find.byKey(const Key('active_route_empty')), findsOneWidget);
    expect(find.byKey(const Key('saved_routes_empty')), findsOneWidget);
    expect(find.text('Створити маршрут'), findsOneWidget);
    expect(find.byKey(const Key('active_empty_create_route')), findsNothing);
    expect(find.text('ОСТАННІ НАПРЯМКИ'), findsNothing);
    await tester.tap(find.byKey(const Key('create_route_cta')));
    expect(created, 1);
  });

  testWidgets('active route uses a dedicated route card with real stats',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: RoutesContent(
        route: activeRoute,
        destination: destination,
        onCreateRoute: () {},
        onOpenDetails: () => opened = true,
      ),
    ));

    expect(find.byKey(const Key('travel_route_card')), findsOneWidget);
    expect(find.text('12.4 км'), findsOneWidget);
    expect(find.text('28 хв'), findsOneWidget);
    expect(find.text('2 точки'), findsOneWidget);
    await tester.tap(find.text('Деталі'));
    expect(opened, isTrue);
  });

  testWidgets('route card hides unavailable optional values', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: TravelRouteCard(title: 'Маршрут без статистики'),
    ));

    expect(find.text('Маршрут без статистики'), findsOneWidget);
    expect(find.byType(RouteMetric), findsNothing);
  });

  testWidgets('route details use fallback, real stats and ordered stops',
      (tester) async {
    var started = false;
    var destinationOpened = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RouteDetailsContent(
          route: activeRoute,
          destination: destination,
          onStart: () => started = true,
          onDestinationTap: () => destinationOpened = true,
        ),
      ),
    ));

    expect(find.byKey(const Key('route_hero_placeholder')), findsOneWidget);
    expect(find.byKey(const Key('route_stats')), findsOneWidget);
    expect(find.text('12.4 км'), findsOneWidget);
    expect(find.text('28 хв'), findsOneWidget);
    expect(find.byKey(const Key('route_stop_number_1')), findsOneWidget);
    expect(find.byKey(const Key('route_stop_number_2')), findsOneWidget);
    expect(find.text('Моя позиція'), findsOneWidget);
    expect(find.text(destination.title), findsOneWidget);
    expect(find.text(destination.description!), findsNothing);

    await tester.tap(find.text(destination.title));
    expect(destinationOpened, isTrue);
    await tester.scrollUntilVisible(
      find.byKey(const Key('start_route_cta')),
      180,
      scrollable: find.byType(Scrollable),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('start_route_cta')));
    expect(started, isTrue);
  });

  testWidgets('route hero uses the real destination image when available',
      (tester) async {
    final withImage = LocationModel(
      id: destination.id,
      userId: destination.userId,
      title: destination.title,
      description: destination.description,
      category: destination.category,
      latitude: destination.latitude,
      longitude: destination.longitude,
      createdAt: destination.createdAt,
      imageUrl: 'https://example.com/route.jpg',
    );
    await tester
        .pumpWidget(MaterialApp(home: RouteHero(destination: withImage)));

    final image =
        tester.widget<Image>(find.byKey(const Key('route_real_image')));
    expect((image.image as NetworkImage).url, withImage.imageUrl);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets('routes and details fit ${width}dp at ${scale}x',
          (tester) async {
        Widget shell(Widget child) => MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 760),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(body: SizedBox(width: width, child: child)),
              ),
            );

        await tester.pumpWidget(shell(RoutesContent(
          route: activeRoute,
          destination: destination,
          onCreateRoute: () {},
          onOpenDetails: () {},
        )));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(shell(RouteDetailsContent(
          route: activeRoute,
          destination: destination,
          onStart: () {},
        )));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
