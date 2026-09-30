import 'package:flutter/material.dart';

/// Journey Phase 1B -- matches [GpsAddMomentSheet.onAdd] to
/// `GpsRecordingController.addWaypoint`'s exact signature (that method has
/// additional optional `latitude`/`longitude`/`altitude` parameters this
/// typedef omits -- a valid, narrower function-type subtype, so the real
/// controller method can be torn off and passed directly with no wrapper).
/// Returns whether a Moment was actually created (the controller's own
/// existing `recording`/`paused`/`no known position yet` rejection cases
/// are preserved, never re-implemented here).
typedef GpsAddMomentCallback = Future<bool> Function({
  required String waypointType,
  String? title,
  String? note,
});

/// Journey Phase 1B -- one canonical `route_waypoint_type` value with its
/// Ukrainian label and icon. Keys are copied verbatim from the enum
/// (`supabase/migrations/202609140002_trips_gps_core.sql`) -- no value
/// invented, none renamed.
class GpsMomentTypeOption {
  const GpsMomentTypeOption(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const gpsMomentTypeOptions = <GpsMomentTypeOption>[
  GpsMomentTypeOption('viewpoint', 'Оглядове місце', Icons.landscape_outlined),
  GpsMomentTypeOption('photo_point', 'Фото', Icons.photo_camera_outlined),
  GpsMomentTypeOption('rest', 'Зупинка / Відпочинок', Icons.chair_alt_outlined),
  GpsMomentTypeOption('interesting_place', 'Цікаве місце', Icons.star_outline),
  GpsMomentTypeOption('water', 'Вода', Icons.water_drop_outlined),
  GpsMomentTypeOption('parking', 'Паркування', Icons.local_parking_outlined),
  GpsMomentTypeOption('campsite', 'Кемпінг', Icons.holiday_village_outlined),
  GpsMomentTypeOption('overnight', 'Ночівля', Icons.nightlight_outlined),
  GpsMomentTypeOption(
      'mountain_pass', 'Гірський перевал', Icons.terrain_outlined),
  GpsMomentTypeOption('danger', 'Небезпека', Icons.warning_amber_outlined),
  GpsMomentTypeOption('custom', 'Інше', Icons.push_pin_outlined),
];

/// Pre-selected type when the sheet opens -- lets a user who just wants a
/// quick marker tap "Додати" immediately, matching the fast path the old
/// silent `waypointType: 'custom'` behavior offered, while still letting
/// anyone pick a more specific type first.
const gpsDefaultMomentType = 'custom';

/// Journey Phase 1B -- opens the Moment-creation bottom sheet. Returns
/// `true` only when a Moment was actually created (mirrors
/// [showGpsDiscardConfirmation]'s "never touches the controller itself"
/// shape: [onAdd] is the only way this sheet reaches production logic,
/// so it stays directly testable with a fake callback and has no
/// `GpsRecordingController` import of its own).
Future<bool?> showGpsAddMomentSheet(
  BuildContext context, {
  required GpsAddMomentCallback onAdd,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => GpsAddMomentSheet(onAdd: onAdd),
    );

/// Public (not underscore-private) so a widget test can pump it directly
/// with a fake [onAdd], the same reasoning already established for
/// [MapCategoriesSheet]/other production sheets in this codebase.
class GpsAddMomentSheet extends StatefulWidget {
  const GpsAddMomentSheet({required this.onAdd, super.key});
  final GpsAddMomentCallback onAdd;

  @override
  State<GpsAddMomentSheet> createState() => _GpsAddMomentSheetState();
}

class _GpsAddMomentSheetState extends State<GpsAddMomentSheet> {
  static const _background = Color(0xFF0D1C17);
  static const _gold = Color(0xFFD4A017);

  String _type = gpsDefaultMomentType;
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Duplicate-tap safety: `_saving` both disables the button (see
  /// `onPressed: _saving ? null : _submit` below) and, defensively, makes
  /// a second call here an immediate no-op even if it were somehow
  /// triggered -- a single user submission can never reach [widget.onAdd]
  /// twice while the first call is still in flight.
  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final title = _titleController.text.trim();
    final note = _noteController.text.trim();
    try {
      final added = await widget.onAdd(
        waypointType: _type,
        title: title.isEmpty ? null : title,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      if (added) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _saving = false;
          _error = 'Не вдалося додати точку подорожі.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не вдалося додати точку подорожі.';
      });
    }
  }

  void _cancel() {
    if (_saving) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              key: const Key('gps_add_moment_sheet'),
              color: _background,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Нова точка подорожі',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            key: const Key('gps_moment_close_button'),
                            tooltip: 'Закрити',
                            onPressed: _saving ? null : _cancel,
                            icon: const Icon(Icons.close, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: gpsMomentTypeOptions
                            .map((option) => ChoiceChip(
                                  key: Key('gps_moment_type_${option.key}'),
                                  avatar: Icon(option.icon, size: 16),
                                  label: Text(option.label,
                                      style: const TextStyle(fontSize: 12)),
                                  selected: _type == option.key,
                                  onSelected: _saving
                                      ? null
                                      : (_) =>
                                          setState(() => _type = option.key),
                                ))
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('gps_moment_title_field'),
                        controller: _titleController,
                        enabled: !_saving,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Назва (необов’язково)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      TextField(
                        key: const Key('gps_moment_note_field'),
                        controller: _noteController,
                        enabled: !_saving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Нотатка (необов’язково)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          key: const Key('gps_moment_error'),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            key: const Key('gps_moment_cancel_button'),
                            onPressed: _saving ? null : _cancel,
                            child: const Text('Скасувати'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            key: const Key('gps_moment_add_button'),
                            onPressed: _saving ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: const Color(0xFF171106),
                            ),
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.add_location_alt_outlined),
                            label: const Text('Додати'),
                          ),
                        ],
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
