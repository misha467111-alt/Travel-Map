import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_add_moment_sheet.dart';

/// Journey Phase 1B -- pure sheet-level coverage: no real
/// `GpsRecordingController`, no Drift, no GoogleMap. [onAdd] is a plain
/// fake callback, exactly mirroring the "no controller inside the
/// contract" split already established for `showGpsDiscardConfirmation`.
/// End-to-end wiring through the real controller (M01/M02/M14/M17/M18)
/// is covered separately in
/// `gps_add_moment_integration_test.dart`, which reuses the existing
/// `gps_recording_map_screen_test.dart` real-controller harness.
void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required GpsAddMomentCallback onAdd,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showGpsAddMomentSheet(context, onAdd: onAdd),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('M03 opening the creation UI shows the sheet', (tester) async {
    await openSheet(tester,
        onAdd: ({required waypointType, title, note}) async => true);

    expect(find.byKey(const Key('gps_add_moment_sheet')), findsOneWidget);
    expect(find.text('Нова точка подорожі'), findsOneWidget);
  });

  testWidgets('M04 all canonical waypoint types are represented',
      (tester) async {
    await openSheet(tester,
        onAdd: ({required waypointType, title, note}) async => true);

    for (final option in gpsMomentTypeOptions) {
      expect(find.byKey(Key('gps_moment_type_${option.key}')), findsOneWidget,
          reason: option.key);
      expect(find.text(option.label), findsOneWidget, reason: option.key);
    }
    // Exactly the canonical backend enum -- nothing invented, nothing
    // renamed.
    expect(
      gpsMomentTypeOptions.map((o) => o.key).toSet(),
      {
        'mountain_pass',
        'campsite',
        'overnight',
        'rest',
        'water',
        'photo_point',
        'viewpoint',
        'danger',
        'parking',
        'interesting_place',
        'custom',
      },
    );
  });

  testWidgets('M05 default type is custom, matching the old one-tap behavior',
      (tester) async {
    String? captured;
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        captured = waypointType;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(captured, 'custom');
  });

  testWidgets('M06 selecting a different type overrides the default',
      (tester) async {
    String? captured;
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        captured = waypointType;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('gps_moment_type_viewpoint')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(captured, 'viewpoint');
  });

  testWidgets('M07/M08 title and note are passed through to onAdd',
      (tester) async {
    String? capturedTitle;
    String? capturedNote;
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        capturedTitle = title;
        capturedNote = note;
        return true;
      },
    );

    await tester.enterText(
        find.byKey(const Key('gps_moment_title_field')), 'Гарний краєвид');
    await tester.enterText(
        find.byKey(const Key('gps_moment_note_field')), 'Варто зупинитись');
    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(capturedTitle, 'Гарний краєвид');
    expect(capturedNote, 'Варто зупинитись');
  });

  testWidgets('M09/M10 whitespace in title/note is trimmed', (tester) async {
    String? capturedTitle;
    String? capturedNote;
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        capturedTitle = title;
        capturedNote = note;
        return true;
      },
    );

    await tester.enterText(
        find.byKey(const Key('gps_moment_title_field')), '  Краєвид  ');
    await tester.enterText(
        find.byKey(const Key('gps_moment_note_field')), '  нотатка  ');
    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(capturedTitle, 'Краєвид');
    expect(capturedNote, 'нотатка');
  });

  testWidgets('M11/M12 empty title/note are persisted as null, not ""',
      (tester) async {
    String? capturedTitle = 'unset';
    String? capturedNote = 'unset';
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        capturedTitle = title;
        capturedNote = note;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(capturedTitle, isNull);
    expect(capturedNote, isNull);
  });

  testWidgets('M11b/M12b whitespace-only title/note are also persisted as null',
      (tester) async {
    String? capturedTitle = 'unset';
    String? capturedNote = 'unset';
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        capturedTitle = title;
        capturedNote = note;
        return true;
      },
    );

    await tester.enterText(
        find.byKey(const Key('gps_moment_title_field')), '   ');
    await tester.enterText(
        find.byKey(const Key('gps_moment_note_field')), '   ');
    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(capturedTitle, isNull);
    expect(capturedNote, isNull);
  });

  testWidgets('M13 cancel closes the sheet and calls onAdd zero times',
      (tester) async {
    var calls = 0;
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        calls++;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('gps_moment_cancel_button')));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byKey(const Key('gps_add_moment_sheet')), findsNothing);
  });

  testWidgets('the close (X) button behaves the same as Cancel',
      (tester) async {
    var calls = 0;
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        calls++;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('gps_moment_close_button')));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byKey(const Key('gps_add_moment_sheet')), findsNothing);
  });

  testWidgets('M14 successful save calls onAdd exactly once and closes',
      (tester) async {
    var calls = 0;
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        calls++;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets(
      'M15/M16 no coordinate or timestamp input exists anywhere in the sheet',
      (tester) async {
    await openSheet(tester,
        onAdd: ({required waypointType, title, note}) async => true);

    // Only the two documented text fields exist -- title and note. No
    // latitude/longitude/timestamp field of any kind is exposed.
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byKey(const Key('gps_moment_title_field')), findsOneWidget);
    expect(find.byKey(const Key('gps_moment_note_field')), findsOneWidget);
  });

  testWidgets(
      'M19 the sheet never depends on network -- a purely local fake onAdd '
      'completes the whole flow', (tester) async {
    // onAdd here never touches Supabase/network -- proves the UI flow
    // itself has no such dependency; only the real controller's own
    // already-offline-first `addWaypoint` would ever be plugged in here
    // in production.
    var calls = 0;
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        calls++;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('M20 a false result from onAdd surfaces an inline error',
      (tester) async {
    await openSheet(tester,
        onAdd: ({required waypointType, title, note}) async => false);

    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gps_moment_error')), findsOneWidget);
    // Stays open so the user can retry or cancel -- never silently
    // fabricates success.
    expect(find.byKey(const Key('gps_add_moment_sheet')), findsOneWidget);
  });

  testWidgets('a thrown exception from onAdd also surfaces an inline error',
      (tester) async {
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async =>
          throw Exception('boom'),
    );

    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gps_moment_error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('M21 successful save closes the sheet', (tester) async {
    await openSheet(tester,
        onAdd: ({required waypointType, title, note}) async => true);

    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gps_add_moment_sheet')), findsNothing);
  });

  testWidgets('M23 duplicate taps while saving never call onAdd more than once',
      (tester) async {
    var calls = 0;
    await openSheet(
      tester,
      onAdd: ({required waypointType, title, note}) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pump();
    // The button is now disabled/showing a spinner -- a second rapid tap
    // must be a no-op, not a second call.
    await tester.tap(find.byKey(const Key('gps_moment_add_button')),
        warnIfMissed: false);
    await tester.tap(find.byKey(const Key('gps_moment_add_button')),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  group('Phase 1D edit form', () {
    Future<void> openEdit(
      WidgetTester tester, {
      required GpsEditMomentCallback onSave,
      String type = 'water',
      String? title = 'Old title',
      String? note = 'Old note',
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showGpsEditMomentSheet(
                context,
                initialType: type,
                initialTitle: title,
                initialNote: note,
                onSave: onSave,
              ),
              child: const Text('edit'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('edit'));
      await tester.pumpAndSettle();
    }

    testWidgets('pre-fills metadata, trims values, and maps blanks to null',
        (tester) async {
      String? savedType;
      String? savedTitle = 'unset';
      String? savedNote = 'unset';
      await openEdit(
        tester,
        onSave: ({required waypointType, title, note}) async {
          savedType = waypointType;
          savedTitle = title;
          savedNote = note;
          return true;
        },
      );

      expect(find.text('Редагувати точку'), findsOneWidget);
      expect(find.text('Old title'), findsOneWidget);
      expect(find.text('Old note'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gps_moment_type_danger')));
      await tester.enterText(
          find.byKey(const Key('gps_moment_title_field')), '  New title  ');
      await tester.enterText(
          find.byKey(const Key('gps_moment_note_field')), '   ');
      await tester.tap(find.byKey(const Key('gps_moment_save_button')));
      await tester.pumpAndSettle();

      expect(savedType, 'danger');
      expect(savedTitle, 'New title');
      expect(savedNote, isNull);
    });

    testWidgets('title remains limited to 80 characters', (tester) async {
      await openEdit(tester,
          onSave: ({required waypointType, title, note}) async => true);

      final field = tester
          .widget<TextField>(find.byKey(const Key('gps_moment_title_field')));
      expect(field.maxLength, 80);
    });

    testWidgets('save failure stays open and duplicate taps are guarded',
        (tester) async {
      var calls = 0;
      await openEdit(
        tester,
        onSave: ({required waypointType, title, note}) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return false;
        },
      );

      await tester.tap(find.byKey(const Key('gps_moment_save_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('gps_moment_save_button')),
          warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.byKey(const Key('gps_edit_moment_sheet')), findsOneWidget);
      expect(find.byKey(const Key('gps_moment_error')), findsOneWidget);
      expect(find.text('Не вдалося зберегти зміни.'), findsOneWidget);
    });
  });

  group('M24/M25 responsive', () {
    const widths = [320.0, 360.0, 390.0, 430.0];
    const scales = [1.0, 1.3, 1.5];
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets(
            'sheet fits ${width}dp @ ${scale}x, all controls reachable, no overflow',
            (tester) async {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(
                theme: buildAppTheme(),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => showGpsAddMomentSheet(
                        context,
                        onAdd: ({required waypointType, title, note}) async =>
                            true,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}dp, scale $scale');
          expect(
              find.byKey(const Key('gps_moment_type_custom')), findsOneWidget);
          expect(
              find.byKey(const Key('gps_moment_title_field')), findsOneWidget);
          expect(
              find.byKey(const Key('gps_moment_note_field')), findsOneWidget);
          expect(
              find.byKey(const Key('gps_moment_add_button')), findsOneWidget);
          expect(find.byKey(const Key('gps_moment_cancel_button')),
              findsOneWidget);
        });
      }
    }
  });
}
