import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_replay_controls.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_playback.dart';

GpsReplayControlsState _state({
  Duration current = const Duration(seconds: 5),
  Duration total = const Duration(seconds: 60),
  double fraction = 0.25,
  bool isPlaying = false,
  GpsReplaySpeed speed = GpsReplaySpeed.one,
  bool canPlay = true,
}) =>
    GpsReplayControlsState(
      current: current,
      total: total,
      fraction: fraction,
      isPlaying: isPlaying,
      speed: speed,
      canPlay: canPlay,
    );

class _Calls {
  int playPause = 0;
  final speeds = <GpsReplaySpeed>[];
  int start = 0;
  final scrubs = <double>[];
  int end = 0;
  int cancel = 0;
}

Widget _app(GpsReplayControlsState state, _Calls calls) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: GpsJourneyReplayControls(
            state: state,
            onPlayPause: () => calls.playPause++,
            onSpeed: calls.speeds.add,
            onScrubStart: () => calls.start++,
            onScrub: calls.scrubs.add,
            onScrubEnd: () => calls.end++,
            onScrubCancel: () => calls.cancel++,
          ),
        ),
      ),
    );

void main() {
  test('C01 time formatting', () {
    expect(formatGpsReplayTime(Duration.zero), '0:00');
    expect(formatGpsReplayTime(const Duration(seconds: 65)), '1:05');
    expect(
        formatGpsReplayTime(const Duration(hours: 1, seconds: 3)), '1:00:03');
    expect(formatGpsReplayTime(const Duration(milliseconds: -5)), '0:00');
  });

  test('C02 state equality', () {
    expect(_state(), _state());
    expect(_state(), isNot(_state(fraction: 0.3)));
    expect(_state().hashCode, _state().hashCode);
  });

  testWidgets('C03 shows current and total time and the right play icon',
      (tester) async {
    await tester.pumpWidget(_app(_state(), _Calls()));
    expect(find.text('0:05'), findsOneWidget);
    expect(find.text('1:00'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.pumpWidget(_app(_state(isPlaying: true), _Calls()));
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('C04 play/pause and speed callbacks', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(_state(), calls));
    await tester.tap(find.byKey(const Key('gps_replay_play_pause')));
    expect(calls.playPause, 1);
    await tester.tap(find.byKey(const Key('gps_replay_speed_0.5x')));
    await tester.tap(find.byKey(const Key('gps_replay_speed_2x')));
    await tester.tap(find.byKey(const Key('gps_replay_speed_4x')));
    expect(calls.speeds,
        [GpsReplaySpeed.half, GpsReplaySpeed.two, GpsReplaySpeed.four]);
    final selected = tester
        .widget<SegmentedButton<GpsReplaySpeed>>(
            find.byKey(const Key('gps_replay_speed')))
        .selected;
    expect(selected, {GpsReplaySpeed.one});
  });

  testWidgets('C05 dragging the slider reports start, values and end',
      (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(_state(), calls));
    await tester.drag(
        find.byKey(const Key('gps_replay_slider')), const Offset(60, 0));
    await tester.pump();
    expect(calls.start, 1);
    expect(calls.scrubs, isNotEmpty);
    expect(calls.scrubs.every((v) => v >= 0 && v <= 1), isTrue);
    expect(calls.end, 1);
    expect(calls.cancel, 0);
  });

  testWidgets('C06 a cancelled pointer reports onScrubCancel', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(_state(), calls));
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('gps_replay_slider'))));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(calls.cancel, 1);
  });

  testWidgets('C07 a Journey that cannot play disables the controls',
      (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(_state(canPlay: false, fraction: 1), calls));
    await tester.tap(find.byKey(const Key('gps_replay_play_pause')),
        warnIfMissed: false);
    expect(calls.playPause, 0);
    expect(
        tester
            .widget<Slider>(find.byKey(const Key('gps_replay_slider')))
            .onChanged,
        isNull);
  });

  testWidgets('C08 fits a narrow screen at a large text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 640), textScaler: TextScaler.linear(1.5)),
      child:
          _app(_state(total: const Duration(hours: 1, seconds: 1)), _Calls()),
    ));
    expect(tester.takeException(), isNull);
  });
}
