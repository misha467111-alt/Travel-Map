import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_design.dart';
import '../local/gps_local_database.dart';
import 'gps_add_moment_sheet.dart';
import 'gps_photo_capture.dart';

typedef GpsEditMomentPersist = Future<bool> Function(
  LocalWaypoint moment, {
  required String waypointType,
  String? title,
  String? note,
});

typedef GpsDeleteMomentPersist = Future<bool> Function(LocalWaypoint moment);

/// Journey Phase 1H-C: saves a photo picked for one Moment. Returns a
/// non-null result on success, `null` if not allowed; throws on failure.
typedef GpsMomentPhotoPersist = Future<Object?> Function(
    LocalWaypoint moment, Uint8List bytes);

/// Presentation-only metadata for a persisted waypoint type. Persistence
/// remains the canonical string stored in [LocalWaypoint.waypointType].
class GpsMomentPresentation {
  const GpsMomentPresentation({
    required this.label,
    required this.icon,
    required this.markerHue,
  });

  final String label;
  final IconData icon;
  final double markerHue;
}

GpsMomentPresentation gpsMomentPresentation(String waypointType) {
  final option = gpsMomentTypeOptions.cast<GpsMomentTypeOption?>().firstWhere(
        (candidate) => candidate?.key == waypointType,
        orElse: () => null,
      );
  final fallback = gpsMomentTypeOptions.last;
  final resolved = option ?? fallback;
  final hue = switch (waypointType) {
    'danger' => BitmapDescriptor.hueRed,
    'water' => BitmapDescriptor.hueAzure,
    'campsite' || 'overnight' => BitmapDescriptor.hueGreen,
    'photo_point' || 'viewpoint' => BitmapDescriptor.hueViolet,
    'parking' => BitmapDescriptor.hueBlue,
    'mountain_pass' => BitmapDescriptor.hueOrange,
    _ => BitmapDescriptor.hueYellow,
  };
  return GpsMomentPresentation(
    label: resolved.label,
    icon: resolved.icon,
    markerHue: hue,
  );
}

String formatGpsMomentTime(DateTime recordedAt) {
  final local = recordedAt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// Pure read-only projection from persisted waypoints to Google Map markers.
/// Positions are copied verbatim; no current-position lookup, snapping, or
/// route-progress calculation occurs here.
Set<Marker> buildGpsMomentMarkers(List<LocalWaypoint> moments) =>
    moments.map((moment) {
      final presentation = gpsMomentPresentation(moment.waypointType);
      return Marker(
        markerId: MarkerId('journey_moment_${moment.id}'),
        position: LatLng(moment.latitude, moment.longitude),
        zIndexInt: 500,
        icon: BitmapDescriptor.defaultMarkerWithHue(presentation.markerHue),
        infoWindow: InfoWindow(
          title: moment.title ?? presentation.label,
          snippet: moment.title == null
              ? formatGpsMomentTime(moment.recordedAt)
              : '${presentation.label} • '
                  '${formatGpsMomentTime(moment.recordedAt)}',
        ),
      );
    }).toSet();

class GpsMomentInspectionButton extends StatelessWidget {
  const GpsMomentInspectionButton({
    required this.momentCount,
    required this.onPressed,
    super.key,
  });

  final int momentCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: const Key('gps_moment_inspection_button'),
        onPressed: onPressed,
        icon: const Icon(Icons.place_outlined),
        label: Text('Точки подорожі ($momentCount)'),
      );
}

Future<void> showGpsMomentsSheet(
  BuildContext context, {
  required List<LocalWaypoint> moments,
  Stream<List<LocalWaypoint>>? momentsStream,
  GpsEditMomentPersist? onEdit,
  GpsDeleteMomentPersist? onDelete,
  List<LocalJourneyMediaItem> media = const [],
  Stream<List<LocalJourneyMediaItem>>? mediaStream,
  GpsPhotoSource? photoSource,
  GpsMomentPhotoPersist? onAddPhoto,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GpsMomentsSheet(
        moments: moments,
        momentsStream: momentsStream,
        onEdit: onEdit,
        onDelete: onDelete,
        media: media,
        mediaStream: mediaStream,
        photoSource: photoSource,
        onAddPhoto: onAddPhoto,
      ),
    );

class GpsMomentsSheet extends StatelessWidget {
  const GpsMomentsSheet({
    required this.moments,
    this.momentsStream,
    this.onEdit,
    this.onDelete,
    this.media = const [],
    this.mediaStream,
    this.photoSource,
    this.onAddPhoto,
    super.key,
  });

  final List<LocalWaypoint> moments;
  final Stream<List<LocalWaypoint>>? momentsStream;
  final GpsEditMomentPersist? onEdit;
  final GpsDeleteMomentPersist? onDelete;

  /// Journey Phase 1H-C: persisted media (only its Moment links are used,
  /// for the per-row photo count) and the photo-adding capability. Adding is
  /// offered only when both [photoSource] and [onAddPhoto] are given.
  final List<LocalJourneyMediaItem> media;
  final Stream<List<LocalJourneyMediaItem>>? mediaStream;
  final GpsPhotoSource? photoSource;
  final GpsMomentPhotoPersist? onAddPhoto;

  Future<void> _edit(BuildContext context, LocalWaypoint moment) async {
    final edit = onEdit;
    if (edit == null) return;
    await showGpsEditMomentSheet(
      context,
      initialType: moment.waypointType,
      initialTitle: moment.title,
      initialNote: moment.note,
      onSave: ({required waypointType, title, note}) => edit(
        moment,
        waypointType: waypointType,
        title: title,
        note: note,
      ),
    );
  }

  Future<void> _delete(BuildContext context, LocalWaypoint moment) async {
    final delete = onDelete;
    if (delete == null) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => GpsDeleteMomentDialog(
        onDelete: () => delete(moment),
      ),
    );
  }

  Widget? _trailing(
    BuildContext context,
    LocalWaypoint moment,
    List<LocalJourneyMediaItem> liveMedia,
  ) {
    final photoCount =
        liveMedia.where((item) => item.waypointId == moment.id).length;
    final source = photoSource;
    final addPhoto = onAddPhoto;
    final canAddPhoto = source != null && addPhoto != null;
    final hasMenu = onEdit != null || onDelete != null;
    if (photoCount == 0 && !canAddPhoto && !hasMenu) return null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (photoCount > 0)
          KeyedSubtree(
            key: Key('gps_moment_photo_count_${moment.id}'),
            child: GpsMomentPhotoCount(count: photoCount),
          ),
        if (canAddPhoto)
          GpsAddPhotoButton(
            key: Key('gps_moment_add_photo_${moment.id}'),
            compact: true,
            tooltip: 'Додати фото до точки',
            source: source,
            save: (bytes) => addPhoto(moment, bytes),
          ),
        if (hasMenu)
          PopupMenuButton<String>(
            key: Key('gps_moment_actions_${moment.id}'),
            tooltip: 'Дії',
            onSelected: (action) {
              if (action == 'edit') {
                _edit(context, moment);
              } else if (action == 'delete') {
                _delete(context, moment);
              }
            },
            itemBuilder: (_) => [
              if (onEdit != null)
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Редагувати'),
                ),
              if (onDelete != null)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Видалити'),
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<LocalWaypoint>>(
        stream: momentsStream,
        initialData: moments,
        builder: (context, snapshot) =>
            StreamBuilder<List<LocalJourneyMediaItem>>(
          stream: mediaStream,
          initialData: media,
          builder: (context, mediaSnapshot) => _buildSheet(
            context,
            snapshot.data ?? moments,
            mediaSnapshot.data ?? media,
          ),
        ),
      );

  Widget _buildSheet(
    BuildContext context,
    List<LocalWaypoint> liveMoments,
    List<LocalJourneyMediaItem> liveMedia,
  ) =>
      Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Material(
            key: const Key('gps_moments_sheet'),
            color: const Color(0xFF0D1C17),
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Точки подорожі (${liveMoments.length})',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          key: const Key('gps_moments_close_button'),
                          tooltip: 'Закрити',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (liveMoments.isEmpty)
                      const Flexible(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpacing.xl,
                            ),
                            child: Center(
                              child: Text(
                                'У цій подорожі ще немає точок.',
                                key: Key('gps_moments_empty'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          key: const Key('gps_moments_list'),
                          shrinkWrap: true,
                          itemCount: liveMoments.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final moment = liveMoments[index];
                            final presentation =
                                gpsMomentPresentation(moment.waypointType);
                            return ListTile(
                              key: Key('gps_moment_row_${moment.id}'),
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(presentation.icon),
                              title: Text(
                                presentation.label,
                                key: Key('gps_moment_type_${moment.id}'),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (moment.title != null)
                                    Text(
                                      moment.title!,
                                      key: Key('gps_moment_title_${moment.id}'),
                                    ),
                                  if (moment.note != null)
                                    Text(
                                      moment.note!,
                                      key: Key('gps_moment_note_${moment.id}'),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(
                                    formatGpsMomentTime(moment.recordedAt),
                                    key: Key('gps_moment_time_${moment.id}'),
                                  ),
                                ],
                              ),
                              trailing: _trailing(context, moment, liveMedia),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class GpsDeleteMomentDialog extends StatefulWidget {
  const GpsDeleteMomentDialog({required this.onDelete, super.key});

  final Future<bool> Function() onDelete;

  @override
  State<GpsDeleteMomentDialog> createState() => _GpsDeleteMomentDialogState();
}

class _GpsDeleteMomentDialogState extends State<GpsDeleteMomentDialog> {
  bool _deleting = false;
  String? _error;

  Future<void> _confirm() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      final deleted = await widget.onDelete();
      if (!mounted) return;
      if (deleted) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _deleting = false;
          _error = 'Не вдалося видалити точку подорожі.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'Не вдалося видалити точку подорожі.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('gps_delete_moment_dialog'),
        title: const Text('Видалити точку подорожі?'),
        content: _error == null
            ? null
            : Text(
                _error!,
                key: const Key('gps_delete_moment_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
        actions: [
          TextButton(
            key: const Key('gps_delete_moment_cancel_button'),
            onPressed:
                _deleting ? null : () => Navigator.of(context).pop(false),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            key: const Key('gps_delete_moment_confirm_button'),
            onPressed: _deleting ? null : _confirm,
            child: _deleting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Видалити'),
          ),
        ],
      );
}
