import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Journey Phase 1H-B -- the app-owned file store for Journey media:
///
///     <application documents directory>/journey_media/<routeId>/<mediaId>.jpg
///
/// Only the RELATIVE path (`journey_media/<routeId>/<mediaId>.jpg`, always
/// with `/`) is ever persisted. The documents-directory root is resolved at
/// use time, because an Android/iOS application container path is not
/// guaranteed to be stable across launches, updates or restores.
///
/// Every operation validates the relative path against the one canonical
/// shape, so a corrupt or hostile value can never resolve outside the media
/// folder. Nothing here touches Drift, the network, or any file outside
/// `journey_media/`.
class JourneyMediaStorage {
  JourneyMediaStorage({required Future<Directory> Function() rootDirectory})
      : _rootDirectory = rootDirectory;

  final Future<Directory> Function() _rootDirectory;

  static const folderName = 'journey_media';
  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final _fileNamePattern = RegExp(r'^[A-Za-z0-9_-]{1,64}\.jpg$');

  /// The canonical relative path for one media file.
  static String relativePathFor({
    required String recordedRouteId,
    required String mediaId,
  }) {
    if (!_idPattern.hasMatch(recordedRouteId) ||
        !_idPattern.hasMatch(mediaId)) {
      throw ArgumentError('route/media ids must be simple identifiers');
    }
    return '$folderName/$recordedRouteId/$mediaId.jpg';
  }

  /// Whether [relativePath] has exactly the canonical shape.
  static bool isValidRelativePath(String relativePath) {
    final parts = relativePath.split('/');
    return parts.length == 3 &&
        parts[0] == folderName &&
        _idPattern.hasMatch(parts[1]) &&
        _fileNamePattern.hasMatch(parts[2]);
  }

  /// Resolves [relativePath] under the CURRENT documents root. Throws
  /// [ArgumentError] for anything but the canonical shape. Does not require
  /// the file to exist.
  Future<File> resolve(String relativePath) async {
    if (!isValidRelativePath(relativePath)) {
      throw ArgumentError.value(
          relativePath, 'relativePath', 'not a canonical journey media path');
    }
    final root = await _rootDirectory();
    return File.fromUri(root.uri.resolve(relativePath));
  }

  /// The file if the path is valid AND the file currently exists, else
  /// `null`. Never throws for a missing/invalid file, so a missing file
  /// degrades to an "unavailable" state instead of a crash.
  Future<File?> existingFile(String relativePath) async {
    if (!isValidRelativePath(relativePath)) return null;
    try {
      final file = await resolve(relativePath);
      return await file.exists() ? file : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Writes [bytes] to [relativePath] atomically (temp file in the same
  /// directory, then rename), creating the route folder as needed. Refuses
  /// to overwrite: an existing file at that path means an identity
  /// collision, which must never silently replace someone's photo. On any
  /// failure the temp file is removed and nothing is left at the target.
  Future<void> writeNew(String relativePath, Uint8List bytes) async {
    final target = await resolve(relativePath);
    if (await target.exists()) {
      throw FileSystemException('media file already exists', target.path);
    }
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Best effort: a stale .tmp is never referenced by any row.
      }
      rethrow;
    }
  }

  /// Best-effort removal of exactly one canonical media file (and its route
  /// folder if that leaves it empty). Missing files and invalid paths are
  /// ignored; never throws for I/O problems -- a leftover file is harmless
  /// (no row points at it), while a failing delete must never block a
  /// database lifecycle operation that already committed.
  Future<void> deleteFile(String relativePath) async {
    if (!isValidRelativePath(relativePath)) return;
    try {
      final file = await resolve(relativePath);
      if (await file.exists()) await file.delete();
      final dir = file.parent;
      if (await dir.exists() && await dir.list().isEmpty) {
        await dir.delete();
      }
    } on FileSystemException {
      // See above.
    }
  }

  /// [deleteFile] for several paths.
  Future<void> deleteFiles(Iterable<String> relativePaths) async {
    for (final path in relativePaths) {
      await deleteFile(path);
    }
  }
}

/// The production store, rooted at the platform's app-owned documents
/// directory (private to the app on both Android and iOS). Resolved lazily,
/// so nothing touches `path_provider` until media is actually used.
final journeyMediaStorageProvider = Provider<JourneyMediaStorage>(
  (ref) => JourneyMediaStorage(rootDirectory: getApplicationDocumentsDirectory),
);
