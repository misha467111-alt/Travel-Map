import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_design.dart';
import '../recording/gps_recording_controller.dart';
import '../recording/gps_recording_state.dart';
import 'gps_recording_map_screen.dart';
import 'gps_recording_ui_state.dart';

/// Phase 4E — pure visibility rule for [GpsActiveRecordingBanner]. Not a
/// new state machine: every branch is a direct read of the existing,
/// authoritative [GpsRecordingStatus] (plus, for the error branch,
/// whether a route was ever created).
///
/// - recording/paused: visible (there is a live session).
/// - finishing: visible -- normally near-instant, but staying up through
///   that brief window avoids a one-frame hide-then-reappear-as-completed
///   flicker.
/// - recoverable: visible -- this is Phase 4E's whole "recovery surface"
///   requirement; it reuses this same indicator and entry point rather
///   than a second, recovery-specific banner/state machine.
/// - permissionError/serviceError/otherError: visible only if
///   [GpsRecordingState.routeId] is set. A mid-session failure (e.g. the
///   position stream erroring) never calls `pause()`/`discard()`, so the
///   *local* route is still open -- a non-null routeId is exactly that
///   "session evidence" the task asks to derive visibility from. A
///   permission/service error with no routeId yet (failed before any
///   route was ever created) has nothing to return to, so it behaves
///   like idle.
/// - idle/preparing/completed: hidden. `completed` hiding the indicator
///   is an explicit Phase 4E product rule -- the just-finished route's
///   own sync state is shown on [GpsRecordingMapScreen] itself (see
///   `GpsRecordingMapBody`'s `completed` case), not here.
bool gpsActiveRecordingIndicatorVisible(GpsRecordingState state) {
  switch (state.status) {
    case GpsRecordingStatus.recording:
    case GpsRecordingStatus.paused:
    case GpsRecordingStatus.finishing:
    case GpsRecordingStatus.recoverable:
      return true;
    case GpsRecordingStatus.permissionError:
    case GpsRecordingStatus.serviceError:
    case GpsRecordingStatus.otherError:
      return state.routeId != null;
    case GpsRecordingStatus.idle:
    case GpsRecordingStatus.preparing:
    case GpsRecordingStatus.completed:
      return false;
  }
}

/// Phase 4E — the smallest persistent surface proving an active or
/// recoverable GPS recording is never "invisible" just because the user
/// left [GpsRecordingMapScreen]. Meant to sit inside
/// `MainNavigationScreen`'s `bottomNavigationBar` slot, above the
/// existing 5-tab bar -- it does not add a tab, and it is visible from
/// every tab since it lives outside the tab `IndexedStack`.
///
/// Thin outer wrapper only (same shape as `GpsRecordingMapScreen`/
/// `GpsRecordingScreen`'s own auth-gated wrappers): resolves the owner id
/// and delegates everything else to [GpsActiveRecordingBannerBody], which
/// is what tests actually exercise (a live Supabase session cannot be
/// simulated in a widget test).
class GpsActiveRecordingBanner extends StatelessWidget {
  const GpsActiveRecordingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const SizedBox.shrink();
    return GpsActiveRecordingBannerBody(ownerId: userId);
  }
}

/// The real, testable body. Public only so tests can construct it
/// directly with an injected [ownerId] -- exactly the same reason
/// `GpsRecordingMapBody` is public.
///
/// Deliberately the *only* widget in the whole shell that watches
/// [gpsRecordingStateProvider]: that stream emits on every accepted GPS
/// point (see `GpsRecordingController._onPosition`), so keeping the
/// watch scoped to this one small widget means `MainNavigationScreen`
/// itself and every page inside its `IndexedStack` never rebuild because
/// of GPS activity. It never touches `gpsRoutePointsProvider` (the
/// route's full point history) at all.
class GpsActiveRecordingBannerBody extends ConsumerWidget {
  const GpsActiveRecordingBannerBody({super.key, required this.ownerId});

  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(gpsRecordingStateProvider(ownerId));
    final state = stateAsync.value;
    if (state == null || !gpsActiveRecordingIndicatorVisible(state)) {
      return const SizedBox.shrink();
    }

    final uiState = mapGpsRecordingUiState(state);
    return _BannerContent(
      key: const Key('gps_active_recording_banner'),
      label: uiState.statusLabel,
      isRecoverable: uiState.isRecoverable,
    );
  }
}

class _BannerContent extends StatefulWidget {
  const _BannerContent({
    super.key,
    required this.label,
    required this.isRecoverable,
  });

  final String label;
  final bool isRecoverable;

  @override
  State<_BannerContent> createState() => _BannerContentState();
}

class _BannerContentState extends State<_BannerContent> {
  /// Guards against a rapid double-tap pushing [GpsRecordingMapScreen]
  /// twice (Phase 4E's own "avoid stacking unlimited duplicate
  /// GpsRecordingMapScreen routes" requirement). Structurally, this
  /// banner is only ever reachable/visible while `MainNavigationScreen`
  /// (or a page inside it) is the topmost route -- if
  /// [GpsRecordingMapScreen] is already pushed on top, the banner
  /// underneath it is not on screen and cannot be tapped at all. This
  /// flag is the direct, cheap, still-useful defense against the one
  /// remaining case that reasoning doesn't cover: two taps landing
  /// before the first push's frame is processed.
  bool _opening = false;

  Future<void> _open(BuildContext context) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const GpsRecordingMapScreen(),
      ));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              widget.isRecoverable ? Icons.history : Icons.fiber_manual_record,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                widget.label,
                key: const Key('gps_active_recording_banner_label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              key: const Key('gps_active_recording_banner_action'),
              onPressed: _opening ? null : () => _open(context),
              child: const Text('Повернутися'),
            ),
          ],
        ),
      ),
    );
  }
}
