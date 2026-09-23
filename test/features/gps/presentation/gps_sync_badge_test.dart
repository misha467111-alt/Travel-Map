import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_sync_badge.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_sync_ui_state.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

void main() {
  testWidgets('C13 notSynced presentation: label shown, retry offered',
      (tester) async {
    var retryTaps = 0;
    await tester.pumpWidget(_wrap(GpsSyncBadge(
      sync: mapGpsSyncUiState('not_synced'),
      onRetry: () => retryTaps++,
    )));

    expect(find.text('Збережено на пристрої'), findsOneWidget);
    expect(find.byKey(const Key('gps_sync_retry_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gps_sync_retry_button')));
    await tester.pump();
    expect(retryTaps, 1);
  });

  testWidgets('C14 syncing presentation: progress indicator, no retry',
      (tester) async {
    await tester.pumpWidget(_wrap(GpsSyncBadge(
      sync: mapGpsSyncUiState('syncing'),
      onRetry: () {},
    )));

    expect(find.text('Синхронізація…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('gps_sync_retry_button')), findsNothing);
  });

  testWidgets('C15 synced presentation: success indicator, no retry',
      (tester) async {
    await tester.pumpWidget(_wrap(GpsSyncBadge(
      sync: mapGpsSyncUiState('synced'),
      onRetry: () {},
    )));

    expect(find.text('Синхронізовано'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byKey(const Key('gps_sync_retry_button')), findsNothing);
  });

  testWidgets('C16 failed presentation: error indicator, retry offered',
      (tester) async {
    var retryTaps = 0;
    await tester.pumpWidget(_wrap(GpsSyncBadge(
      sync: mapGpsSyncUiState('failed'),
      onRetry: () => retryTaps++,
    )));

    expect(find.text('Помилка синхронізації'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byKey(const Key('gps_sync_retry_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gps_sync_retry_button')));
    await tester.pump();
    expect(retryTaps, 1);
  });

  testWidgets('never relies on color alone: every state has a distinct icon',
      (tester) async {
    Future<IconData?> iconFor(String status) async {
      await tester
          .pumpWidget(_wrap(GpsSyncBadge(sync: mapGpsSyncUiState(status))));
      final icons = find.byType(Icon);
      if (icons.evaluate().isEmpty) return null;
      return tester.widget<Icon>(icons.first).icon;
    }

    final notSynced = await iconFor('not_synced');
    final synced = await iconFor('synced');
    final failed = await iconFor('failed');

    expect(notSynced, isNot(equals(synced)));
    expect(synced, isNot(equals(failed)));
    expect(notSynced, isNot(equals(failed)));
  });
}
