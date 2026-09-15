import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:uuid/uuid.dart';

import '../location/location_permission_service.dart';
import '../location/location_permission_state.dart';
import '../location/location_source.dart';
import '../location/notification_permission_source.dart';
import '../local/gps_local_database.dart';
import '../local/gps_local_database_provider.dart';
import 'gps_recording_state.dart';
import 'gps_sample_validation.dart';

/// Owns one account's GPS recording session end to end: permission/service
/// readiness, starting the position stream, sample validation, persisting
/// every accepted point through the GPS-2 Drift layer (never raw SQL from
/// this class), pause/resume/finish/discard, waypoints, app-lifecycle-aware
/// stream suspension, and crash/restart recovery detection.
///
/// Plain class + `Provider`, not a Riverpod `Notifier` — deliberately
/// mirrors the already-proven pattern this exact codebase uses for
/// `ChatConversationController` (manual broadcast `StreamController` + a
/// companion `StreamProvider` for the UI), for the same reason established
/// there: this Riverpod version's family-notifier API has no documented
/// public base class this codebase uses anywhere.
///
/// [gpsRecordingControllerProvider] is deliberately **not** `.autoDispose`
/// (GPS-4B1): an active recording is a session, not a screen-local widget
/// concern — it must survive the user navigating to Map/Explore/Profile/
/// Settings and back, which an `autoDispose` family provider cannot
/// guarantee, since it tears down (cancelling [_positionSub] with it) the
/// moment its last UI watcher unmounts. The controller instance now lives
/// for the `ProviderContainer`'s lifetime once first created for a given
/// [_ownerId], exactly like this codebase's existing
/// `gpsLocalDatabaseProvider`, and is disposed only at container teardown.
///
/// Entirely free of any direct Supabase dependency, unlike an earlier
/// draft of this class: "confirm authenticated user" (task 5) is
/// satisfied by construction, not by a redundant runtime check here —
/// [gpsRecordingControllerProvider] is keyed by an explicit [ownerId]
/// the caller already derives from
/// `Supabase.instance.client.auth.currentUser`.id (see
/// `GpsRecordingDebugScreen`, and the same pattern already used by
/// `blockingActiveRecordingId`'s thin Supabase-touching wrapper). This
/// keeps the controller's actual recording logic directly unit-testable
/// with a plain in-memory database and a fake location source, with no
/// live Supabase session required at all.
class GpsRecordingController with WidgetsBindingObserver {
  GpsRecordingController({
    required String ownerId,
    required GpsLocalDatabase db,
    required LocationSource locationSource,
    required NotificationPermissionSource notificationPermissionSource,
  })  : _ownerId = ownerId,
        _db = db,
        _locationSource = locationSource,
        _notificationPermissionSource = notificationPermissionSource,
        _permissionService = LocationPermissionService(locationSource) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_detectRecoverableRecording());
  }

  final String _ownerId;
  final GpsLocalDatabase _db;
  final LocationSource _locationSource;
  final NotificationPermissionSource _notificationPermissionSource;
  final LocationPermissionService _permissionService;

  final _stateController = StreamController<GpsRecordingState>.broadcast();
  GpsRecordingState _state = GpsRecordingState.idle;

  /// Emits the current state immediately for each UI subscriber, then all
  /// subsequent transitions. A raw broadcast controller has no replay, so
  /// exposing it directly leaves a [StreamProvider] permanently loading when
  /// a new controller finds no recoverable recording and therefore emits no
  /// transition during construction.
  Stream<GpsRecordingState> get stateStream => Stream<GpsRecordingState>.multi(
        (listener) {
          listener.add(_state);
          final subscription = _stateController.stream.listen(
            listener.add,
            onError: listener.addError,
            onDone: listener.close,
          );
          listener.onCancel = subscription.cancel;
        },
        isBroadcast: true,
      );
  GpsRecordingState get state => _state;

  StreamSubscription<Position>? _positionSub;

  bool _disposed = false;

  /// Read-only observability seam (GPS-4B1): [WidgetsBinding] exposes no
  /// public way to confirm an observer was actually removed, so this
  /// minimal flag exists purely so a test can confirm [dispose] ran (e.g.
  /// at `ProviderContainer` teardown) without exposing any other internal
  /// state. Not meant for production call sites — see
  /// `gps_recording_controller_provider_test.dart`'s container-disposal
  /// test for its one real use.
  @visibleForTesting
  bool get isDisposed => _disposed;

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_positionSub?.cancel());
    _stateController.close();
  }

  void _emit(GpsRecordingState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  // ---------------------------------------------------------------------
  // Crash / app-restart recovery (task 14)
  // ---------------------------------------------------------------------

  Future<void> _detectRecoverableRecording() async {
    final recoverable = await _db.getRecoverableRecording(_ownerId);
    if (recoverable == null) return;
    if (_state.status != GpsRecordingStatus.idle) return;
    final pointCount = (await _db.getRoutePoints(
            ownerId: _ownerId, recordedRouteId: recoverable.id))
        .length;
    debugPrint('gps recovery: found unfinished route (points=$pointCount)');
    _emit(_state.copyWith(
      status: GpsRecordingStatus.recoverable,
      routeId: recoverable.id,
      pointCount: pointCount,
      startedAt: recoverable.startedAt,
      transportMode: recoverable.transportMode,
    ));
  }

  /// Explicit user choice from the [GpsRecordingStatus.recoverable]
  /// state: resume sampling on the existing route (whatever its DB
  /// status — recording or paused — resumeRecording only actually
  /// changes it if it was 'paused'; a 'recording' row is already in the
  /// right status and resumeRecording is a documented no-op for that
  /// case).
  Future<void> resumeRecoverableRecording() async {
    if (_state.status != GpsRecordingStatus.recoverable ||
        _state.routeId == null) {
      return;
    }
    final routeId = _state.routeId!;
    final route = await _db.getRecordedRoute(ownerId: _ownerId, id: routeId);
    if (route == null) {
      _emit(GpsRecordingState.idle);
      return;
    }
    if (route.status == RecordedRouteStatus.paused) {
      await _resumeInternal(routeId);
    } else {
      await _startStreamAndEmitRecording(routeId, route.transportMode);
    }
  }

  Future<void> finishRecoverableRecording() async {
    if (_state.status != GpsRecordingStatus.recoverable ||
        _state.routeId == null) {
      return;
    }
    await _finishInternal(_state.routeId!);
  }

  Future<void> discardRecoverableRecording() async {
    if (_state.status != GpsRecordingStatus.recoverable ||
        _state.routeId == null) {
      return;
    }
    await _discardInternal(_state.routeId!);
  }

  // ---------------------------------------------------------------------
  // Start (task 5)
  // ---------------------------------------------------------------------

  Future<void> start({
    String? tripId,
    String? title,
    String transportMode = 'walking',
    String visibility = 'private',
  }) async {
    if (_state.status == GpsRecordingStatus.recoverable) {
      // "Never start a second route while one is recoverable."
      debugPrint('gps start: blocked, a recoverable recording exists');
      return;
    }
    if (_state.status == GpsRecordingStatus.recording ||
        _state.status == GpsRecordingStatus.paused) {
      debugPrint('gps start: blocked, already recording/paused');
      return;
    }

    _emit(_state.copyWith(status: GpsRecordingStatus.preparing));

    final readiness = await _permissionService.ensureReady();
    if (readiness != LocationReadiness.granted) {
      debugPrint('gps start: permission/service not ready ($readiness)');
      _emit(_state.copyWith(
        status: readiness == LocationReadiness.serviceDisabled
            ? GpsRecordingStatus.serviceError
            : GpsRecordingStatus.permissionError,
        readiness: readiness,
      ));
      return;
    }

    final routeId = const Uuid().v4();
    final startedAt = DateTime.now().toUtc();
    try {
      await _db.createLocalRecordedRoute(
        id: routeId,
        ownerId: _ownerId,
        tripId: tripId,
        title: title,
        transportMode: transportMode,
        visibility: visibility,
        startedAt: startedAt,
      );
    } on ActiveRecordingExistsException catch (_) {
      debugPrint('gps start: rejected by ActiveRecordingExistsException');
      _emit(_state.copyWith(
          status: GpsRecordingStatus.otherError,
          errorMessage: 'already recording'));
      return;
    }

    await _startStreamAndEmitRecording(routeId, transportMode,
        startedAt: startedAt);
  }

  /// Shared by [start] and [resumeRecoverableRecording]'s "still
  /// recording" branch: subscribes to the position stream and only then
  /// emits the 'recording' state. If subscribing itself fails (task 5's
  /// explicit "stream startup fails after local route creation" case),
  /// the just-created/still-existing local route is deliberately left
  /// untouched (still a valid, recoverable 'recording' row) — only the
  /// in-memory state reflects the failure, so the UI never shows a fake
  /// healthy recording, but no local data is destroyed either.
  ///
  /// This is also the one place [_ensureNotificationPermissionRequested]
  /// is called (GPS-4B2.1): every path that (re)starts the position
  /// stream — `start()`, an explicit `resume()`, and
  /// `resumeRecoverableRecording()`'s already-recording branch — shares
  /// this method, so the request naturally happens lazily on each of
  /// them without duplicating the call at each call site.
  Future<void> _startStreamAndEmitRecording(
    String routeId,
    String transportMode, {
    DateTime? startedAt,
  }) async {
    await _ensureNotificationPermissionRequested();
    try {
      _subscribeToPositionStream(routeId);
    } catch (error) {
      debugPrint('gps start: position stream failed to start');
      _emit(_state.copyWith(
        status: GpsRecordingStatus.otherError,
        routeId: routeId,
        errorMessage: 'location stream failed to start',
      ));
      return;
    }
    final pointCount =
        (await _db.getRoutePoints(ownerId: _ownerId, recordedRouteId: routeId))
            .length;
    _emit(GpsRecordingState(
      status: GpsRecordingStatus.recording,
      routeId: routeId,
      pointCount: pointCount,
      startedAt: startedAt ?? _state.startedAt,
      transportMode: transportMode,
    ));
    debugPrint('gps: position stream started for route');
  }

  /// Android 13+ only (GPS-4B2.1): lazily requests `POST_NOTIFICATIONS`
  /// exactly when a recording is about to (re)start its position stream —
  /// i.e. exactly when the foreground-service notification this
  /// permission controls is about to appear. Never requested at app
  /// launch, never requested for any reason other than an active
  /// recording actually (re)starting.
  ///
  /// Deliberately never gates recording on the outcome: confirmed against
  /// current Android developer documentation that a location foreground
  /// service remains fully standards-compliant and functional with or
  /// without this permission — a denial only suppresses the notification
  /// drawer entry, the service and the recording itself are unaffected
  /// either way (see `GpsSamplingSettings`'s Android notification config).
  /// The outcome is only logged, not stored in [GpsRecordingState] — no
  /// current UI needs to surface it, and adding a field for it now would
  /// be speculative; a future production recording screen can add one
  /// if/when it actually needs to show this to the user.
  ///
  /// iOS is never touched by this at all, regardless of platform-checked
  /// outcome — `permission_handler`'s iOS implementation is present only
  /// as an unavoidable transitive dependency of the federated
  /// `permission_handler` plugin and is never invoked from any iOS code
  /// path; GPS-4B2/GPS-4B2.1 stay Android-only.
  Future<void> _ensureNotificationPermissionRequested() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final granted = await _notificationPermissionSource.request();
    debugPrint('gps: notification permission '
        '${granted ? 'granted' : 'denied'} (recording is not blocked '
        'either way)');
  }

  void _subscribeToPositionStream(String routeId) {
    unawaited(_positionSub?.cancel());
    _positionSub = _locationSource
        .getPositionStream(settings: GpsSamplingSettings.forCurrentPlatform())
        .listen(
      (position) => unawaited(_onPosition(routeId, position)),
      onError: (Object error, StackTrace stackTrace) {
        // A stream error must never corrupt local state -- the local
        // route/points already persisted are untouched; only the
        // in-memory state reflects the failure.
        debugPrint(
            'gps: position stream error, recording state preserved locally');
        _emit(_state.copyWith(
          status: GpsRecordingStatus.otherError,
          errorMessage: 'location stream error',
        ));
      },
    );
  }

  Future<void> _onPosition(String routeId, Position position) async {
    final sample = validateGpsSample(position);
    if (sample == null) {
      debugPrint('gps: rejected 1 invalid sample');
      return;
    }
    await _db.appendRoutePoint(
      ownerId: _ownerId,
      recordedRouteId: routeId,
      latitude: sample.latitude,
      longitude: sample.longitude,
      altitude: sample.altitude,
      horizontalAccuracy: sample.horizontalAccuracy,
      verticalAccuracy: sample.verticalAccuracy,
      speed: sample.speed,
      speedAccuracy: sample.speedAccuracy,
      heading: sample.heading,
      headingAccuracy: sample.headingAccuracy,
      recordedAt: sample.recordedAt,
    );
    if (_state.routeId == routeId) {
      _emit(_state.copyWith(
          lastAccepted: sample, pointCount: _state.pointCount + 1));
    }
  }

  // ---------------------------------------------------------------------
  // Pause / resume (tasks 9, 10)
  // ---------------------------------------------------------------------

  /// Cancels the position subscription *before* touching the database —
  /// no more samples are accepted once pause is requested, rather than
  /// continuing to receive and silently drop them until the DB write
  /// completes.
  Future<void> pause() async {
    if (_state.status != GpsRecordingStatus.recording ||
        _state.routeId == null) {
      return;
    }
    final routeId = _state.routeId!;
    await _positionSub?.cancel();
    _positionSub = null;
    await _db.pauseRecording(
      ownerId: _ownerId,
      routeId: routeId,
      occurredAt: DateTime.now().toUtc(),
    );
    debugPrint('gps: paused');
    _emit(_state.copyWith(status: GpsRecordingStatus.paused));
  }

  Future<void> resume() async {
    if (_state.status != GpsRecordingStatus.paused || _state.routeId == null) {
      return;
    }
    await _resumeInternal(_state.routeId!);
  }

  Future<void> _resumeInternal(String routeId) async {
    final readiness = await _permissionService.ensureReady();
    if (readiness != LocationReadiness.granted) {
      debugPrint('gps resume: permission/service not ready ($readiness)');
      _emit(_state.copyWith(
        status: readiness == LocationReadiness.serviceDisabled
            ? GpsRecordingStatus.serviceError
            : GpsRecordingStatus.permissionError,
        readiness: readiness,
      ));
      return;
    }
    await _db.resumeRecording(
      ownerId: _ownerId,
      routeId: routeId,
      occurredAt: DateTime.now().toUtc(),
    );
    // _subscribeToPositionStream always cancels any prior subscription
    // first -- prevents a duplicate active subscription regardless of
    // how resume was reached.
    await _startStreamAndEmitRecording(
        routeId, _state.transportMode ?? 'walking');
    debugPrint('gps: resumed');
  }

  // ---------------------------------------------------------------------
  // Finish / discard (tasks 11, 12)
  // ---------------------------------------------------------------------

  Future<void> finish() async {
    if (_state.status != GpsRecordingStatus.recording &&
        _state.status != GpsRecordingStatus.paused) {
      return;
    }
    if (_state.routeId == null) return;
    await _finishInternal(_state.routeId!);
  }

  Future<void> _finishInternal(String routeId) async {
    _emit(_state.copyWith(status: GpsRecordingStatus.finishing));
    await _positionSub?.cancel();
    _positionSub = null;
    await _db.finishRecordingLocally(
      ownerId: _ownerId,
      routeId: routeId,
      occurredAt: DateTime.now().toUtc(),
    );
    debugPrint(
        'gps: finished (completed locally; server finalize is future sync work)');
    _emit(_state.copyWith(status: GpsRecordingStatus.completed));
  }

  Future<void> discard() async {
    if (_state.status != GpsRecordingStatus.recording &&
        _state.status != GpsRecordingStatus.paused) {
      return;
    }
    if (_state.routeId == null) return;
    await _discardInternal(_state.routeId!);
  }

  Future<void> _discardInternal(String routeId) async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _db.discardRecording(
      ownerId: _ownerId,
      routeId: routeId,
      occurredAt: DateTime.now().toUtc(),
    );
    // Raw GPS data is deliberately never erased here -- only the route's
    // status changes. Whether discarded recordings are eventually
    // cleaned up is an explicit future decision, not made in GPS-3.
    debugPrint('gps: discarded (raw local data retained)');
    _emit(GpsRecordingState.idle);
  }

  // ---------------------------------------------------------------------
  // Waypoints (task 15)
  // ---------------------------------------------------------------------

  /// Available while recording or paused (no other status). Uses the
  /// most recently accepted position when [latitude]/[longitude] are
  /// omitted; the caller may instead pass explicit coordinates (e.g. a
  /// future "drop pin on map" waypoint flow) per the existing GPS-2
  /// `addWaypoint` contract. Photo attachment is out of scope for
  /// GPS-3 -- `photoRef` stays null.
  Future<void> addWaypoint({
    required String waypointType,
    String? title,
    String? note,
    double? latitude,
    double? longitude,
    double? altitude,
  }) async {
    if (_state.status != GpsRecordingStatus.recording &&
        _state.status != GpsRecordingStatus.paused) {
      debugPrint('gps addWaypoint: rejected, not recording/paused');
      return;
    }
    final routeId = _state.routeId;
    if (routeId == null) return;

    final lat = latitude ?? _state.lastAccepted?.latitude;
    final lng = longitude ?? _state.lastAccepted?.longitude;
    if (lat == null || lng == null) {
      debugPrint('gps addWaypoint: rejected, no known position yet');
      return;
    }

    await _db.addWaypoint(
      id: const Uuid().v4(),
      ownerId: _ownerId,
      recordedRouteId: routeId,
      waypointType: waypointType,
      title: title,
      note: note,
      latitude: lat,
      longitude: lng,
      altitude: altitude ?? _state.lastAccepted?.altitude,
      recordedAt: DateTime.now().toUtc(),
    );
    debugPrint('gps: waypoint added');
  }

  // ---------------------------------------------------------------------
  // App lifecycle (GPS-4B2)
  // ---------------------------------------------------------------------

  /// GPS-4B2, deliberately changed from GPS-3/GPS-4B1's foreground-only
  /// rule: while actively recording, no app-lifecycle transition touches
  /// [_positionSub] at all, in either direction.
  ///
  /// On Android, every subscription created for an active recording is
  /// already started with `foregroundNotificationConfig` set (see
  /// [GpsSamplingSettings]), which is what legitimately keeps the same
  /// stream delivering updates while the app is backgrounded or the
  /// screen is locked — the OS foreground service is the thing that
  /// survives backgrounding, not any Dart-side suspend/resume dance, so
  /// there is nothing left for this method to suspend or restart.
  /// Reintroducing a cancel-on-background/resubscribe-on-foreground step
  /// here (GPS-3/GPS-4B1's old behavior) would just tear down and
  /// immediately recreate the same subscription for no reason, and risks
  /// a real seq/duplicate-subscription bug for no benefit.
  ///
  /// On iOS, `allowBackgroundLocationUpdates` is still `false` (GPS-4B2
  /// is Android-only — see [GpsSamplingSettings]'s doc), so in practice
  /// the OS itself still suspends iOS location delivery while
  /// backgrounded; this method not fighting that is correct, not an
  /// oversight — there is nothing productive it could do differently
  /// until GPS-4B4 changes the iOS settings too.
  ///
  /// When no recording is active, [_positionSub] is already null (no
  /// other code path ever subscribes outside an active recording), so
  /// every case below is a no-op by construction, not by an explicit
  /// guard — there are no "background location resources" to hold onto
  /// in the first place.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    switch (lifecycleState) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}

final gpsRecordingControllerProvider =
    Provider.family<GpsRecordingController, String>((ref, ownerId) {
  final db = ref.watch(gpsLocalDatabaseProvider);
  final controller = GpsRecordingController(
    ownerId: ownerId,
    db: db,
    locationSource: const GeolocatorLocationSource(),
    notificationPermissionSource: const PermissionHandlerNotificationSource(),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// UI-facing reactive state — same pattern as
/// `chatConversationStateProvider`: a plain `StreamProvider.family`
/// wrapping the controller's manually-managed stream.
///
/// Deliberately still `.autoDispose`, unlike
/// [gpsRecordingControllerProvider] above: this provider is only a thin
/// reactive relay (it holds no state and owns no resources beyond a
/// stream subscription), so it is safe and preferable to let Riverpod
/// tear it down when no UI is watching. The upstream controller keeps
/// running regardless — it does not depend on this provider staying
/// alive — and [GpsRecordingController.stateStream]'s `Stream.multi`
/// replay (see its doc comment) guarantees a freshly re-watched instance
/// of this provider immediately receives the controller's current state,
/// not a stale or missed one, so no UI state is ever lost across a
/// navigate-away-and-back.
final gpsRecordingStateProvider = StreamProvider.autoDispose
    .family<GpsRecordingState, String>((ref, ownerId) {
  return ref.watch(gpsRecordingControllerProvider(ownerId)).stateStream;
});
