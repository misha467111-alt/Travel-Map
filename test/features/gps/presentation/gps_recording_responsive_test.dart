import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_controls.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_header.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_status_card.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_ui_state.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_sync_ui_state.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';

/// Mirrors the responsive-fit pattern already used elsewhere in this
/// suite (e.g. `create_location_screen_test.dart`, `batch8_review_
/// settings_test.dart`): a real `SizedBox` width constraint plus
/// `MediaQuery` data for text scale, checked purely for absence of
/// overflow.
Widget _shellAt(double width, double scale) {
  final uiState = mapGpsRecordingUiState(const GpsRecordingState(
    status: GpsRecordingStatus.recording,
    routeId: 'r1',
    pointCount: 12,
  ));
  final sync = mapGpsSyncUiState('not_synced');

  return MaterialApp(
    theme: buildAppTheme(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 760),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: SafeArea(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GpsRecordingHeader(uiState: uiState, onBack: () {}),
                  const SizedBox(height: AppSpacing.lg),
                  GpsRecordingStatusCard(uiState: uiState, sync: sync),
                  const SizedBox(height: AppSpacing.lg),
                  GpsRecordingControls(
                    uiState: uiState,
                    onPause: () {},
                    onFinish: () {},
                    onAddWaypoint: () {},
                    onDiscard: () {},
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

void main() {
  // C18 -- typical Android/iPhone-sized viewports, default text scale.
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('C18 fits ${width}dp at 1.0x, no overflow', (tester) async {
      await tester.pumpWidget(_shellAt(width, 1.0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  // C19 -- text-scale sanity across the same viewport range.
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.3, 1.5]) {
      testWidgets('C19 fits ${width}dp at ${scale}x, no overflow',
          (tester) async {
        await tester.pumpWidget(_shellAt(width, scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
