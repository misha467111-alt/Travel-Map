import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_live_moments.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_photo_capture.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_controls.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_ui_state.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';
import 'package:flutter_application_1/features/map/domain/location_photo_normalizer.dart';

final _t0 = DateTime.utc(2026, 3, 5, 10, 30);

class _FakeSource implements GpsPhotoSource {
  _FakeSource({this.result, this.error});
  Uint8List? result;
  Object? error;
  final picked = <GpsPhotoSourceKind>[];

  @override
  Future<Uint8List?> pick(GpsPhotoSourceKind kind) async {
    picked.add(kind);
    if (error != null) throw error!;
    return result;
  }
}

LocalWaypoint _moment(String id, {String? title}) => LocalWaypoint(
      id: id,
      recordedRouteId: 'r1',
      ownerId: 'me',
      waypointType: 'viewpoint',
      title: title,
      latitude: 50,
      longitude: 30,
      recordedAt: _t0,
      createdAt: _t0,
      updatedAt: _t0,
      syncStatus: WaypointSyncStatus.pending,
    );

LocalJourneyMediaItem _media(String id, {String? waypointId}) =>
    LocalJourneyMediaItem(
      id: id,
      ownerId: 'me',
      recordedRouteId: 'r1',
      waypointId: waypointId,
      mediaType: JourneyMediaType.image,
      capturedAt: _t0,
      localRelativePath: 'journey_media/r1/$id.jpg',
      syncStatus: JourneyMediaSyncStatus.pending,
      createdAt: _t0,
      updatedAt: _t0,
    );

Widget _app(Widget child, {double width = 390, double scale = 1.0}) =>
    MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(
            size: Size(width, 800), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    );

final _bytes = Uint8List.fromList([1, 2, 3]);

Future<void> _chooseAndSettle(WidgetTester tester, Key sourceKey,
    {bool settle = true}) async {
  await tester.tap(find.byKey(const Key('gps_add_photo_button')));
  // The busy spinner animates forever, so pumpAndSettle cannot be used
  // while the chooser is open.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byKey(sourceKey));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  group('capture flow', () {
    Future<List<Uint8List>> pumpButton(
      WidgetTester tester,
      _FakeSource source, {
      Future<Object?> Function(Uint8List)? save,
    }) async {
      final saved = <Uint8List>[];
      await tester.pumpWidget(_app(GpsAddPhotoButton(
        source: source,
        save: save ??
            (bytes) async {
              saved.add(bytes);
              return Object();
            },
      )));
      return saved;
    }

    testWidgets('1 camera success saves the picked bytes and confirms',
        (tester) async {
      final source = _FakeSource(result: _bytes);
      final saved = await pumpButton(tester, source);

      await _chooseAndSettle(tester, const Key('gps_photo_source_camera'));

      expect(source.picked, [GpsPhotoSourceKind.camera]);
      expect(saved, [_bytes]);
      expect(find.text('Фото додано'), findsOneWidget);
    });

    testWidgets('2 gallery success saves the picked bytes and confirms',
        (tester) async {
      final source = _FakeSource(result: _bytes);
      final saved = await pumpButton(tester, source);

      await _chooseAndSettle(tester, const Key('gps_photo_source_gallery'));

      expect(source.picked, [GpsPhotoSourceKind.gallery]);
      expect(saved, [_bytes]);
      expect(find.text('Фото додано'), findsOneWidget);
    });

    testWidgets('the chooser offers exactly Камера and Галерея',
        (tester) async {
      await pumpButton(tester, _FakeSource());
      await tester.tap(find.byKey(const Key('gps_add_photo_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Камера'), findsOneWidget);
      expect(find.text('Галерея'), findsOneWidget);
    });

    testWidgets('3 cancelling the chooser is silent and saves nothing',
        (tester) async {
      final source = _FakeSource(result: _bytes);
      final saved = await pumpButton(tester, source);

      await tester.tap(find.byKey(const Key('gps_add_photo_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(const Offset(5, 5)); // dismiss via the barrier
      await tester.pumpAndSettle();

      expect(source.picked, isEmpty);
      expect(saved, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('3 cancelling the picker is silent and saves nothing',
        (tester) async {
      final source = _FakeSource(result: null);
      final saved = await pumpButton(tester, source);

      await _chooseAndSettle(tester, const Key('gps_photo_source_camera'));

      expect(source.picked, [GpsPhotoSourceKind.camera]);
      expect(saved, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a picker failure is reported plainly and saves nothing',
        (tester) async {
      final source = _FakeSource(error: StateError('camera busy'));
      final saved = await pumpButton(tester, source);

      await _chooseAndSettle(tester, const Key('gps_photo_source_camera'));

      expect(saved, isEmpty);
      expect(
          find.text('Не вдалося відкрити камеру або галерею.'), findsOneWidget);
      expect(find.textContaining('camera busy'), findsNothing);
    });

    for (final entry in <String, Object>{
      '4 an unsupported image': const UnsupportedLocationPhotoFormat(),
      '5 a missing Moment': JourneyMediaTargetException('gone'),
      '5 a Journey finished mid-photo':
          JourneyMediaRouteNotActiveException(RecordedRouteStatus.completed),
      '5 a storage/database failure': StateError('disk full'),
    }.entries) {
      testWidgets('${entry.key} is shown safely, never as raw text',
          (tester) async {
        await pumpButton(tester, _FakeSource(result: _bytes),
            save: (_) => Future<Object?>.error(entry.value));

        await _chooseAndSettle(tester, const Key('gps_photo_source_gallery'));

        expect(find.text(describeGpsPhotoError(entry.value)), findsOneWidget);
        expect(find.text('Фото додано'), findsNothing);
        expect(find.textContaining('disk full'), findsNothing);
        expect(find.textContaining('gone'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a disallowed state (save returns null) never claims success',
        (tester) async {
      await pumpButton(tester, _FakeSource(result: _bytes),
          save: (_) async => null);

      await _chooseAndSettle(tester, const Key('gps_photo_source_camera'));

      expect(find.text('Фото зараз не можна додати.'), findsOneWidget);
      expect(find.text('Фото додано'), findsNothing);
    });

    testWidgets('6 duplicate taps while saving are ignored', (tester) async {
      final gate = Completer<Object?>();
      var saves = 0;
      await pumpButton(tester, _FakeSource(result: _bytes), save: (_) {
        saves++;
        return gate.future;
      });

      await _chooseAndSettle(tester, const Key('gps_photo_source_camera'),
          settle: false);
      expect(saves, 1);
      expect(find.byKey(const Key('gps_photo_busy')), findsOneWidget);

      await tester.tap(find.byKey(const Key('gps_add_photo_button')),
          warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const Key('gps_photo_source_sheet')), findsNothing,
          reason: 'a busy button opens no second chooser');
      expect(saves, 1);

      gate.complete(Object());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gps_photo_busy')), findsNothing);
      expect(find.text('Фото додано'), findsOneWidget);
    });

    test('error copy is plain Ukrainian, one message per class', () {
      expect(describeGpsPhotoError(const UnsupportedLocationPhotoFormat()),
          contains('не підтримується'));
      expect(describeGpsPhotoError(JourneyMediaTargetException('x')),
          contains('точку подорожі не знайдено'));
      expect(
          describeGpsPhotoError(JourneyMediaRouteNotActiveException(
              RecordedRouteStatus.completed)),
          'Подорож уже завершено, тому фото не додано.');
      expect(describeGpsPhotoError(Exception('boom')),
          'Не вдалося зберегти фото. Спробуйте ще раз.');
    });
  });

  group('Moment rows', () {
    Widget sheet({
      List<LocalWaypoint>? moments,
      Stream<List<LocalJourneyMediaItem>>? mediaStream,
      List<LocalJourneyMediaItem> media = const [],
      GpsPhotoSource? photoSource,
      GpsMomentPhotoPersist? onAddPhoto,
      double width = 390,
      double scale = 1.0,
    }) =>
        _app(
          GpsMomentsSheet(
            moments: moments ?? [_moment('m1'), _moment('m2')],
            media: media,
            mediaStream: mediaStream,
            photoSource: photoSource,
            onAddPhoto: onAddPhoto,
            onEdit: (m, {required waypointType, title, note}) async => true,
            onDelete: (m) async => true,
          ),
          width: width,
          scale: scale,
        );

    testWidgets('no photo controls without the capability', (tester) async {
      await tester.pumpWidget(sheet());

      expect(find.byKey(const Key('gps_moment_add_photo_m1')), findsNothing);
      expect(find.byKey(const Key('gps_moment_photo_count_m1')), findsNothing);
    });

    testWidgets('7 adding for a row saves for exactly that Moment',
        (tester) async {
      final attached = <String>[];
      await tester.pumpWidget(sheet(
        photoSource: _FakeSource(result: _bytes),
        onAddPhoto: (moment, bytes) async {
          attached.add(moment.id);
          return Object();
        },
      ));

      await tester.tap(find.byKey(const Key('gps_moment_add_photo_m2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('gps_photo_source_camera')));
      await tester.pumpAndSettle();

      expect(attached, ['m2']);
    });

    testWidgets('20 the count indicator follows the persisted media stream',
        (tester) async {
      final controller =
          StreamController<List<LocalJourneyMediaItem>>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(sheet(
        mediaStream: controller.stream,
        photoSource: _FakeSource(),
        onAddPhoto: (m, b) async => Object(),
      ));
      expect(find.byKey(const Key('gps_moment_photo_count_m1')), findsNothing);

      controller.add([_media('a', waypointId: 'm1')]);
      await tester.pump();
      expect(
          find.byKey(const Key('gps_moment_photo_count_m1')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('gps_moment_photo_count_m1')),
              matching: find.text('1')),
          findsOneWidget);

      controller.add([
        _media('a', waypointId: 'm1'),
        _media('b', waypointId: 'm1'),
        _media('c'), // standalone: no Moment count
        _media('d', waypointId: 'm2'),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
          find.descendant(
              of: find.byKey(const Key('gps_moment_photo_count_m1')),
              matching: find.text('2')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('gps_moment_photo_count_m2')),
              matching: find.text('1')),
          findsOneWidget);
    });

    testWidgets('21 a media row whose local file is missing still renders',
        (tester) async {
      // The path does not exist on disk: the indicator is metadata-only, so
      // nothing is resolved, decoded or deleted.
      await tester.pumpWidget(sheet(media: [_media('gone', waypointId: 'm1')]));

      expect(
          find.byKey(const Key('gps_moment_photo_count_m1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('availability on the controls', () {
    Widget controls(GpsRecordingStatus status) => _app(GpsRecordingControls(
          uiState: mapGpsRecordingUiState(GpsRecordingState(status: status)),
          photoButton: GpsAddPhotoButton(
              source: _FakeSource(), save: (_) async => Object()),
        ));

    for (final status in [
      GpsRecordingStatus.recording,
      GpsRecordingStatus.paused,
    ]) {
      testWidgets('$status offers the photo action', (tester) async {
        await tester.pumpWidget(controls(status));

        expect(find.byKey(const Key('gps_add_photo_button')), findsOneWidget);
      });
    }

    for (final status in [
      GpsRecordingStatus.completed,
      GpsRecordingStatus.idle,
      GpsRecordingStatus.recoverable,
      GpsRecordingStatus.finishing,
    ]) {
      testWidgets('15/16 $status offers no photo action', (tester) async {
        await tester.pumpWidget(controls(status));

        expect(find.byKey(const Key('gps_add_photo_button')), findsNothing);
      });
    }
  });

  group('Responsive', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('controls and Moment rows fit ${width}dp @ ${scale}x',
            (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_app(
            Column(children: [
              GpsRecordingControls(
                uiState: mapGpsRecordingUiState(const GpsRecordingState(
                    status: GpsRecordingStatus.recording)),
                momentCount: 12,
                onViewMoments: () {},
                photoButton: GpsAddPhotoButton(
                    count: 12,
                    source: _FakeSource(),
                    save: (_) async => Object()),
              ),
              Expanded(
                child: GpsMomentsSheet(
                  moments: [
                    _moment('m1',
                        title: 'Дуже довга назва точки подорожі, яка не '
                            'повинна переповнювати екран'),
                  ],
                  media: [
                    for (var i = 0; i < 12; i++) _media('p$i', waypointId: 'm1')
                  ],
                  photoSource: _FakeSource(),
                  onAddPhoto: (m, b) async => Object(),
                  onEdit: (m, {required waypointType, title, note}) async =>
                      true,
                  onDelete: (m) async => true,
                ),
              ),
            ]),
            width: width,
            scale: scale,
          ));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('gps_add_photo_button')), findsWidgets);
        });
      }
    }
  });
}
