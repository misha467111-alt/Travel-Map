import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../local/gps_local_database.dart';
import '../media/journey_media_storage.dart';

/// Journey Phase 1H-D -- read-only presentation of a completed Journey's
/// local photos.
///
/// Everything here is local and passive: the only input is persisted media
/// METADATA, and the only file access is `JourneyMediaStorage.existingFile`
/// (the one validated boundary for canonical app-owned files), performed
/// lazily for a thumbnail only when that thumbnail is built. Nothing here
/// writes, deletes, tombstones or changes sync state, and there is no
/// network, location or capture code.
const gpsPhotoUnavailableText = 'Фото недоступне на цьому пристрої';
const gpsMediaTypeUnsupportedText = 'Цей тип медіа не підтримується';

/// Longest decoded edge (in physical pixels) for list thumbnails: a bounded
/// decode of the already-normalized (<= 1600 px) canonical file, so a
/// Timeline never holds full-resolution bitmaps for every photo.
const gpsPhotoThumbDecodeWidth = 240;

/// The canonical file for a relative path, or `null` if it is missing or the
/// path is not canonical. Never throws for a missing file.
final gpsJourneyPhotoFileProvider =
    FutureProvider.autoDispose.family<File?, String>((ref, relativePath) {
  return ref.watch(journeyMediaStorageProvider).existingFile(relativePath);
});

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({
    required this.size,
    this.icon = Icons.image_not_supported_outlined,
    this.text,
    this.textKey,
    this.child,
  });

  final double size;
  final IconData icon;
  final String? text;
  final Key? textKey;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: child ??
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              if (text != null)
                Flexible(
                  child: Text(
                    text!,
                    key: textKey,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
    );
  }
}

/// A small square thumbnail. A missing file, an unreadable image or an
/// unknown media type all render a stable placeholder; none of them throws
/// or touches the database.
class GpsJourneyPhotoThumb extends ConsumerWidget {
  const GpsJourneyPhotoThumb({super.key, required this.item, this.size = 88});

  final LocalJourneyMediaItem item;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.mediaType != JourneyMediaType.image) {
      return _PhotoPlaceholder(
        size: size,
        icon: Icons.perm_media_outlined,
        text: gpsMediaTypeUnsupportedText,
        textKey: Key('gps_media_unsupported_${item.id}'),
      );
    }
    final fileAsync =
        ref.watch(gpsJourneyPhotoFileProvider(item.localRelativePath));
    return fileAsync.when(
      loading: () => _PhotoPlaceholder(
        size: size,
        child: const Center(
          child: SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => _unavailable(),
      data: (file) {
        if (file == null) return _unavailable();
        return Semantics(
          button: true,
          label: 'Фото',
          child: InkWell(
            key: Key('gps_photo_thumb_${item.id}'),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            onTap: () => showGpsJourneyPhotoViewer(context, item),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: SizedBox.square(
                dimension: size,
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  cacheWidth: gpsPhotoThumbDecodeWidth,
                  errorBuilder: (_, __, ___) => _unavailable(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _unavailable() => _PhotoPlaceholder(
        size: size,
        text: gpsPhotoUnavailableText,
        textKey: Key('gps_photo_unavailable_${item.id}'),
      );
}

/// Opens a full-screen, read-only viewer for one photo. Pinch-zoom only: no
/// edit, delete, share or capture controls. Resolves the canonical file
/// through the same storage boundary as the thumbnails.
Future<void> showGpsJourneyPhotoViewer(
  BuildContext context,
  LocalJourneyMediaItem item,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => GpsJourneyPhotoViewer(item: item),
    );

class GpsJourneyPhotoViewer extends ConsumerWidget {
  const GpsJourneyPhotoViewer({super.key, required this.item});

  final LocalJourneyMediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileAsync = item.mediaType == JourneyMediaType.image
        ? ref.watch(gpsJourneyPhotoFileProvider(item.localRelativePath))
        : const AsyncData<File?>(null);

    Widget unavailable(String text) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              text,
              key: const Key('gps_photo_viewer_unavailable'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );

    return Dialog.fullscreen(
      key: const Key('gps_photo_viewer'),
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: fileAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => unavailable(gpsPhotoUnavailableText),
              data: (file) => file == null
                  ? unavailable(item.mediaType == JourneyMediaType.image
                      ? gpsPhotoUnavailableText
                      : gpsMediaTypeUnsupportedText)
                  : InteractiveViewer(
                      child: Image.file(
                        file,
                        key: const Key('gps_photo_viewer_image'),
                        fit: BoxFit.contain,
                        // The canonical file is already <= 1600 px; this
                        // only bounds decoding for an unexpected larger one.
                        cacheWidth: 1600,
                        errorBuilder: (_, __, ___) =>
                            unavailable(gpsPhotoUnavailableText),
                      ),
                    ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                key: const Key('gps_photo_viewer_close'),
                tooltip: 'Закрити',
                color: Colors.white,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
