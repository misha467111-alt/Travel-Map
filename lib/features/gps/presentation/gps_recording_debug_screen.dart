import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../location/location_permission_state.dart';
import '../recording/gps_recording_controller.dart';
import '../recording/gps_recording_state.dart';

/// GPS-3's minimal developer/test surface (task 17) — deliberately not
/// the final recorder UI. Exists only to exercise start/pause/resume/
/// waypoint/finish/discard on a real device and see enough live state
/// (status, point count, latest coordinates/accuracy) to verify the
/// recording engine actually works. No map, no styling beyond what
/// `ListTile`/`Card` give for free, no route history browsing.
class GpsRecordingDebugScreen extends ConsumerWidget {
  const GpsRecordingDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Потрібно увійти в акаунт.')),
      );
    }

    final stateAsync = ref.watch(gpsRecordingStateProvider(userId));
    final controller = ref.read(gpsRecordingControllerProvider(userId));

    return Scaffold(
      appBar: AppBar(title: const Text('GPS запис (debug)')),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Помилка: $error')),
        data: (state) => _DebugBody(state: state, controller: controller),
      ),
    );
  }
}

class _DebugBody extends StatelessWidget {
  const _DebugBody({required this.state, required this.controller});

  final GpsRecordingState state;
  final GpsRecordingController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Статус: ${state.status.name}',
                    style: Theme.of(context).textTheme.titleMedium),
                if (state.routeId != null) Text('routeId: ${state.routeId}'),
                Text('Точок збережено: ${state.pointCount}'),
                if (state.lastAccepted case final sample?) ...[
                  Text('Останні координати: '
                      '${sample.latitude.toStringAsFixed(6)}, '
                      '${sample.longitude.toStringAsFixed(6)}'),
                  Text('Точність: '
                      '${sample.horizontalAccuracy?.toStringAsFixed(1) ?? '—'} м'),
                ],
                if (state.startedAt != null) Text('Почато: ${state.startedAt}'),
                if (state.readiness != null)
                  Text('Причина: ${_readinessLabel(state.readiness!)}'),
                if (state.errorMessage != null)
                  Text('Помилка: ${state.errorMessage}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (state.status == GpsRecordingStatus.idle)
              FilledButton(
                onPressed: () => controller.start(),
                child: const Text('Почати запис'),
              ),
            if (state.status == GpsRecordingStatus.recording) ...[
              FilledButton(
                  onPressed: controller.pause, child: const Text('Пауза')),
              OutlinedButton(
                onPressed: () =>
                    controller.addWaypoint(waypointType: 'viewpoint'),
                child: const Text('Додати точку'),
              ),
              FilledButton(
                  onPressed: controller.finish, child: const Text('Завершити')),
              TextButton(
                  onPressed: controller.discard,
                  child: const Text('Скасувати')),
            ],
            if (state.status == GpsRecordingStatus.paused) ...[
              FilledButton(
                  onPressed: controller.resume,
                  child: const Text('Продовжити')),
              OutlinedButton(
                onPressed: () => controller.addWaypoint(waypointType: 'rest'),
                child: const Text('Додати точку'),
              ),
              FilledButton(
                  onPressed: controller.finish, child: const Text('Завершити')),
              TextButton(
                  onPressed: controller.discard,
                  child: const Text('Скасувати')),
            ],
            if (state.status == GpsRecordingStatus.recoverable) ...[
              FilledButton(
                onPressed: controller.resumeRecoverableRecording,
                child: const Text('Відновити'),
              ),
              OutlinedButton(
                onPressed: controller.finishRecoverableRecording,
                child: const Text('Завершити'),
              ),
              TextButton(
                onPressed: controller.discardRecoverableRecording,
                child: const Text('Скасувати'),
              ),
            ],
            if (state.status == GpsRecordingStatus.completed ||
                state.status == GpsRecordingStatus.permissionError ||
                state.status == GpsRecordingStatus.serviceError ||
                state.status == GpsRecordingStatus.otherError)
              FilledButton(
                onPressed: () => controller.start(),
                child: const Text('Новий запис'),
              ),
          ],
        ),
      ],
    );
  }

  String _readinessLabel(LocationReadiness readiness) => switch (readiness) {
        LocationReadiness.serviceDisabled => 'служби геолокації вимкнені',
        LocationReadiness.denied => 'дозвіл відхилено',
        LocationReadiness.deniedForever => 'дозвіл заблоковано назавжди',
        LocationReadiness.granted => 'надано',
      };
}
