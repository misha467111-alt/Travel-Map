import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_details_view.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_photos.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_details.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';

final _t0 = DateTime.utc(2026, 3, 5, 10, 30);
DateTime _at(int min) => _t0.add(Duration(minutes: min));

late Directory _dir;
final _files = <String, File>{};

/// A tiny real JPEG at the canonical-looking relative path, under a temp
/// "documents" directory (never the developer's real one).
void _writePhoto(String id) {
  final rel = 'journey_media/r1/$id.jpg';
  final file = File('${_dir.path}/$rel')..createSync(recursive: true);
  final image = img.Image(width: 16, height: 16, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(30, 120, 60));
  file.writeAsBytesSync(img.encodeJpg(image));
  _files[rel] = file;
}

LocalJourneyMediaItem _media(
  String id, {
  String? waypointId,
  int min = 5,
  String type = JourneyMediaType.image,
}) =>
    LocalJourneyMediaItem(
      id: id,
      ownerId: 'me',
      recordedRouteId: 'r1',
      waypointId: waypointId,
      mediaType: type,
      capturedAt: _at(min),
      localRelativePath: 'journey_media/r1/$id.jpg',
      syncStatus: JourneyMediaSyncStatus.pending,
      createdAt: _at(min),
      updatedAt: _at(min),
    );

LocalWaypoint _moment(String id, int min, {String? title, String? note}) =>
    LocalWaypoint(
      id: id,
      recordedRouteId: 'r1',
      ownerId: 'me',
      waypointType: 'viewpoint',
      title: title,
      note: note,
      latitude: 50.0015,
      longitude: 30.0,
      recordedAt: _at(min),
      createdAt: _at(min),
      updatedAt: _at(min),
      syncStatus: WaypointSyncStatus.pending,
    );

LocalRouteEvent _event(int seq, String type, int min) => LocalRouteEvent(
      recordedRouteId: 'r1',
      seq: seq,
      ownerId: 'me',
      eventType: type,
      occurredAt: _at(min),
    );

GpsJourneyDetails _details({
  List<LocalWaypoint> moments = const [],
  List<LocalJourneyMediaItem> media = const [],
  String sync = RouteSyncStatus.notSynced,
  String? title,
}) =>
    GpsJourneyDetails(
      route: LocalRecordedRoute(
        id: 'r1',
        ownerId: 'me',
        title: title,
        transportMode: 'walking',
        status: RecordedRouteStatus.completed,
        visibility: 'private',
        startedAt: _t0,
        endedAt: _at(60),
        createdAt: _t0,
        updatedAt: _t0,
        syncStatus: sync,
      ),
      points: const [],
      moments: moments,
      media: media,
      statistics: GpsJourneyStatistics.empty,
      timeline: buildGpsJourneyTimeline(
        events: [
          _event(1, RouteEventType.start, 0),
          _event(2, RouteEventType.finish, 60),
        ],
        moments: moments,
        media: media,
      ),
    );

Widget _app(
  Widget child, {
  double width = 390,
  double scale = 1.0,
  GpsJourneyDetails? details,
  Set<String> missing = const {},
  List<String>? resolved,
}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        gpsJourneyDetailsProvider.overrideWith((ref, args) async => details),
        gpsJourneyDetailsRouteProvider
            .overrideWith((ref, args) => const Stream.empty()),
        gpsJourneyPhotoFileProvider.overrideWith((ref, path) async {
          resolved?.add(path);
          return missing.contains(path) ? null : _files[path];
        }),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: child),
        ),
      ),
    );

Widget _body() => const GpsJourneyDetailsBody(ownerId: 'me', routeId: 'r1');

void _tw(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await body(tester);
    });

void main() {
  setUpAll(() {
    _dir = Directory.systemTemp.createTempSync('journey_photos_test_');
    for (final id in ['a', 'b', 'c', 'p1', 'p2', 'solo']) {
      _writePhoto(id);
    }
  });
  tearDownAll(() => _dir.deleteSync(recursive: true));

  group('thumbnail', () {
    _tw(
        'an available photo is decoded at a bounded size from its canonical '
        'file', (tester) async {
      await tester.pumpWidget(_app(GpsJourneyPhotoThumb(item: _media('a'))));
      await tester.pump();

      final image = tester.widget<Image>(find.descendant(
          of: find.byKey(const Key('gps_photo_thumb_a')),
          matching: find.byType(Image)));
      final provider = image.image as ResizeImage;
      expect(provider.width, gpsPhotoThumbDecodeWidth);
      final file = (provider.imageProvider as FileImage).file;
      expect(file.path, _files['journey_media/r1/a.jpg']!.path);
      expect(file.path.startsWith(_dir.path), isTrue,
          reason: 'only the canonical app-owned file is used');
    });

    _tw(
        'D14/D15 a missing file shows the Ukrainian unavailable state, '
        'without error', (tester) async {
      await tester.pumpWidget(_app(
        GpsJourneyPhotoThumb(item: _media('gone')),
        missing: {'journey_media/r1/gone.jpg'},
      ));
      await tester.pump();

      expect(find.text(gpsPhotoUnavailableText), findsOneWidget);
      expect(find.text('Фото недоступне на цьому пристрої'), findsOneWidget);
      expect(find.byKey(const Key('gps_photo_thumb_gone')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('gps_photo_unavailable_gone')),
          warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const Key('gps_photo_viewer')), findsNothing);
    });

    _tw(
        'D28 an unknown media type fails gracefully and never resolves a '
        'file', (tester) async {
      final resolved = <String>[];
      await tester.pumpWidget(_app(
        GpsJourneyPhotoThumb(item: _media('v', type: 'video')),
        resolved: resolved,
      ));
      await tester.pump();

      expect(find.text(gpsMediaTypeUnsupportedText), findsOneWidget);
      expect(resolved, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('viewer', () {
    _tw(
        'D17/D18 tapping a photo opens a read-only viewer of the canonical '
        'file', (tester) async {
      await tester.pumpWidget(_app(GpsJourneyPhotoThumb(item: _media('a'))));
      await tester.pump();

      await tester.tap(find.byKey(const Key('gps_photo_thumb_a')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('gps_photo_viewer')), findsOneWidget);
      final image =
          tester.widget<Image>(find.byKey(const Key('gps_photo_viewer_image')));
      final file =
          ((image.image as ResizeImage).imageProvider as FileImage).file;
      expect(file.path, _files['journey_media/r1/a.jpg']!.path);
      // Read-only: the only control is close.
      expect(
          find.descendant(
              of: find.byKey(const Key('gps_photo_viewer')),
              matching: find.byType(IconButton)),
          findsOneWidget);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);

      await tester.tap(find.byKey(const Key('gps_photo_viewer_close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('gps_photo_viewer')), findsNothing);
    });

    _tw('D23 opening the viewer needs no recording or location provider',
        (tester) async {
      // Only the file provider is overridden; any attempt to read a
      // controller/location provider would throw (Supabase/Geolocator are
      // absent under test).
      await tester.pumpWidget(_app(GpsJourneyPhotoThumb(item: _media('a'))));
      await tester.pump();
      await tester.tap(find.byKey(const Key('gps_photo_thumb_a')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('gps_photo_viewer')), findsOneWidget);
    });

    _tw('a viewer for a missing file shows the unavailable text',
        (tester) async {
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showGpsJourneyPhotoViewer(context, _media('gone')),
            child: const Text('open'),
          ),
        ),
        missing: {'journey_media/r1/gone.jpg'},
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('gps_photo_viewer_unavailable')),
          findsOneWidget);
      expect(find.text(gpsPhotoUnavailableText), findsOneWidget);
    });
  });

  group('Details integration', () {
    _tw('D01/D29 no photos: no thumbnails, no photo entries, no errors',
        (tester) async {
      await tester.pumpWidget(_app(_body(), details: _details()));
      await tester.pumpAndSettle();

      expect(find.byType(GpsJourneyPhotoThumb), findsNothing);
      expect(find.text('Фото'), findsNothing);
      expect(find.byKey(const Key('gps_details_stats')), findsOneWidget);
    });

    _tw('D02/D06 a standalone photo appears as its own Timeline entry',
        (tester) async {
      await tester.pumpWidget(_app(
        _body(),
        details: _details(media: [_media('solo', min: 20)]),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('gps_timeline_media_solo')),
          findsOneWidget);
      expect(find.text('Фото'), findsOneWidget);
      expect(find.byKey(const ValueKey('gps_timeline_photo_solo')),
          findsOneWidget);
    });

    _tw(
        'D03/D04/D05/D25 a Moment with several photos stays ONE row showing '
        'all of them', (tester) async {
      await tester.pumpWidget(_app(
        _body(),
        details: _details(
          moments: [_moment('m1', 10, title: 'Перевал')],
          media: [
            _media('a', waypointId: 'm1', min: 11),
            _media('b', waypointId: 'm1', min: 12),
            _media('c', waypointId: 'm1', min: 13),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('gps_timeline_moment_m1')), findsOneWidget);
      expect(find.text('Перевал'), findsOneWidget);
      final row = find.byKey(const ValueKey('gps_timeline_moment_m1'));
      for (final id in ['a', 'b', 'c']) {
        expect(
            find.descendant(
                of: row,
                matching: find.byKey(ValueKey('gps_timeline_photo_$id'))),
            findsOneWidget);
      }
      expect(find.byKey(const ValueKey('gps_timeline_media_a')), findsNothing,
          reason: 'attached photos create no Timeline entries of their own');
    });

    _tw('D14/D15 a missing photo among others degrades only that photo',
        (tester) async {
      await tester.pumpWidget(_app(
        _body(),
        details: _details(
          moments: [_moment('m1', 10)],
          media: [
            _media('a', waypointId: 'm1', min: 11),
            _media('gone', waypointId: 'm1', min: 12),
          ],
        ),
        missing: {'journey_media/r1/gone.jpg'},
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gps_photo_thumb_a')), findsOneWidget);
      expect(find.text(gpsPhotoUnavailableText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _tw(
        'D20/D21 completed Details offers no capture or media mutation '
        'controls', (tester) async {
      await tester.pumpWidget(_app(
        _body(),
        details: _details(
          moments: [_moment('m1', 10, note: 'Нотатка')],
          media: [
            _media('a', waypointId: 'm1', min: 11),
            _media('solo', min: 20),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gps_add_photo_button')), findsNothing);
      expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byType(PopupMenuButton), findsNothing);
      final timeline = find.byKey(const Key('gps_details_scroll'));
      expect(find.descendant(of: timeline, matching: find.byType(TextField)),
          findsNothing);
    });

    _tw('D24 an unsynced completed Journey shows its photos offline',
        (tester) async {
      await tester.pumpWidget(_app(
        _body(),
        details:
            _details(sync: RouteSyncStatus.notSynced, media: [_media('solo')]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Збережено на пристрої'), findsOneWidget);
      expect(find.byKey(const Key('gps_photo_thumb_solo')), findsOneWidget);
    });

    _tw('D30 many photos are built lazily', (tester) async {
      // Distinct ids so every entry has a stable identity.
      final distinct = [
        for (var i = 0; i < 300; i++)
          LocalJourneyMediaItem(
            id: 'x$i',
            ownerId: 'me',
            recordedRouteId: 'r1',
            mediaType: JourneyMediaType.image,
            capturedAt: _at(1 + (i % 50)),
            localRelativePath: 'journey_media/r1/solo.jpg',
            syncStatus: JourneyMediaSyncStatus.pending,
            createdAt: _t0,
            updatedAt: _t0,
          ),
      ];
      await tester
          .pumpWidget(_app(_body(), details: _details(media: distinct)));
      await tester.pumpAndSettle();

      expect(find.byType(GpsJourneyPhotoThumb).evaluate().length, lessThan(40));
    });

    _tw('D32 the end of a photo-heavy Timeline stays reachable',
        (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      await tester.pumpWidget(_app(
        _body(),
        details: _details(media: [
          for (var i = 0; i < 12; i++)
            LocalJourneyMediaItem(
              id: 'y$i',
              ownerId: 'me',
              recordedRouteId: 'r1',
              mediaType: JourneyMediaType.image,
              capturedAt: _at(1 + i),
              localRelativePath: 'journey_media/r1/solo.jpg',
              syncStatus: JourneyMediaSyncStatus.pending,
              createdAt: _t0,
              updatedAt: _t0,
            ),
        ]),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Подорож завершено'), 400,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Подорож завершено'), findsOneWidget);
    });
  });

  group('Responsive', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('photos fit ${width}dp @ ${scale}x', (tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_app(
            _body(),
            width: width,
            scale: scale,
            missing: {'journey_media/r1/gone.jpg'},
            details: _details(
              title: 'Дуже довга назва подорожі через усі Карпати і ще далі',
              sync: RouteSyncStatus.failed,
              moments: [
                _moment('m1', 10,
                    title: 'Надзвичайно довга назва точки подорожі, яка не '
                        'повинна переповнювати екран',
                    note: 'Дуже довга нотатка ' * 12),
              ],
              media: [
                _media('a', waypointId: 'm1', min: 11),
                _media('b', waypointId: 'm1', min: 12),
                _media('c', waypointId: 'm1', min: 13),
                _media('gone', waypointId: 'm1', min: 14),
                _media('solo', min: 20),
              ],
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.scrollUntilVisible(
              find.byKey(const ValueKey('gps_timeline_media_solo')), 300,
              scrollable: find.byType(Scrollable).first);
          await tester.scrollUntilVisible(find.text('Подорож завершено'), 300,
              scrollable: find.byType(Scrollable).first);
          expect(find.text('Подорож завершено'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
