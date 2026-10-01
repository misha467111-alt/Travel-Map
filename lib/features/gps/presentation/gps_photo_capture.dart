import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_design.dart';
import '../../map/domain/location_photo_normalizer.dart';
import '../local/gps_local_database.dart';

/// Journey Phase 1H-C -- where a Journey photo comes from.
enum GpsPhotoSourceKind { camera, gallery }

/// The picker boundary. A source only ever returns the picked image BYTES
/// (or `null` when the user cancelled): the picker's own file/path is never
/// kept, so an external temp path can never reach the database. The bytes
/// are only INPUT -- the canonical file is always the normalized copy made
/// by `JourneyMediaService`.
abstract interface class GpsPhotoSource {
  Future<Uint8List?> pick(GpsPhotoSourceKind kind);
}

/// The production source: the project's existing `image_picker` (the same
/// package and the same size caps as Create Location). It requests no broad
/// storage access; the system camera/photo picker UI does the work.
class ImagePickerGpsPhotoSource implements GpsPhotoSource {
  const ImagePickerGpsPhotoSource();

  @override
  Future<Uint8List?> pick(GpsPhotoSourceKind kind) async {
    final image = await ImagePicker().pickImage(
      source: kind == GpsPhotoSourceKind.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (image == null) return null;
    return image.readAsBytes();
  }
}

/// Overridden in tests with a fake; never touches a platform channel until a
/// photo is actually requested.
final gpsPhotoSourceProvider =
    Provider<GpsPhotoSource>((ref) => const ImagePickerGpsPhotoSource());

/// Saves picked bytes. Returns a non-null result when the photo was stored,
/// `null` when creation is not allowed right now; throws on failure.
typedef GpsPhotoSave = Future<Object?> Function(Uint8List bytes);

enum GpsPhotoOutcome { saved, cancelled, failed }

/// Plain Ukrainian copy for each failure; never raw exception text.
String describeGpsPhotoError(Object error) {
  if (error is UnsupportedLocationPhotoFormat) {
    return 'Це зображення не підтримується. Оберіть інше фото.';
  }
  if (error is JourneyMediaRouteNotActiveException) {
    return 'Подорож уже завершено, тому фото не додано.';
  }
  if (error is JourneyMediaTargetException) {
    return 'Не вдалося прив’язати фото: точку подорожі не знайдено.';
  }
  return 'Не вдалося зберегти фото. Спробуйте ще раз.';
}

Future<GpsPhotoSourceKind?> showGpsPhotoSourceSheet(BuildContext context) =>
    showModalBottomSheet<GpsPhotoSourceKind>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          key: const Key('gps_photo_source_sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('gps_photo_source_camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Камера'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(GpsPhotoSourceKind.camera),
            ),
            ListTile(
              key: const Key('gps_photo_source_gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Галерея'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(GpsPhotoSourceKind.gallery),
            ),
          ],
        ),
      ),
    );

/// The whole creation flow: choose source -> pick -> save -> feedback.
/// Cancelling at either step is not an error: nothing is saved and nothing
/// is shown.
Future<GpsPhotoOutcome> runGpsPhotoCapture(
  BuildContext context, {
  required GpsPhotoSource source,
  required GpsPhotoSave save,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final kind = await showGpsPhotoSourceSheet(context);
  if (kind == null) return GpsPhotoOutcome.cancelled;

  final Uint8List? bytes;
  try {
    bytes = await source.pick(kind);
  } catch (_) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Не вдалося відкрити камеру або галерею.')));
    return GpsPhotoOutcome.failed;
  }
  if (bytes == null) return GpsPhotoOutcome.cancelled;

  try {
    final saved = await save(bytes);
    if (saved == null) {
      messenger?.showSnackBar(
          const SnackBar(content: Text('Фото зараз не можна додати.')));
      return GpsPhotoOutcome.failed;
    }
  } catch (error) {
    messenger
        ?.showSnackBar(SnackBar(content: Text(describeGpsPhotoError(error))));
    return GpsPhotoOutcome.failed;
  }
  messenger?.showSnackBar(const SnackBar(content: Text('Фото додано')));
  return GpsPhotoOutcome.saved;
}

/// A photo entry point that runs [runGpsPhotoCapture] and blocks further
/// taps while a photo is being picked/saved (shows a spinner instead of the
/// icon). [compact] renders an icon-only button for list rows.
class GpsAddPhotoButton extends StatefulWidget {
  const GpsAddPhotoButton({
    super.key,
    required this.source,
    required this.save,
    this.count = 0,
    this.compact = false,
    this.tooltip = 'Додати фото',
  });

  final GpsPhotoSource source;
  final GpsPhotoSave save;

  /// How many photos this target already has (shown as a label suffix).
  final int count;
  final bool compact;
  final String tooltip;

  @override
  State<GpsAddPhotoButton> createState() => _GpsAddPhotoButtonState();
}

class _GpsAddPhotoButtonState extends State<GpsAddPhotoButton> {
  bool _busy = false;

  Future<void> _onPressed() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runGpsPhotoCapture(context,
          source: widget.source, save: widget.save);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy
        ? const SizedBox.square(
            key: Key('gps_photo_busy'),
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.add_a_photo_outlined);
    if (widget.compact) {
      return IconButton(
        key: const Key('gps_add_photo_button'),
        tooltip: widget.tooltip,
        onPressed: _busy ? null : _onPressed,
        icon: icon,
      );
    }
    return OutlinedButton.icon(
      key: const Key('gps_add_photo_button'),
      onPressed: _busy ? null : _onPressed,
      icon: icon,
      label: Text(widget.count > 0 ? 'Фото (${widget.count})' : 'Додати фото'),
    );
  }
}

/// Small read-only "N photos" marker for a Moment row, driven purely by
/// persisted media metadata (no image is decoded, so a missing file can
/// never break it).
class GpsMomentPhotoCount extends StatelessWidget {
  const GpsMomentPhotoCount({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_outlined, size: 16),
          const SizedBox(width: 2),
          Text('$count'),
        ],
      ),
    );
  }
}
