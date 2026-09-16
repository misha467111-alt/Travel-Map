import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_design.dart';
import '../domain/location_categories.dart';
import '../domain/location_metadata.dart';
import '../domain/location_photo_normalizer.dart';
import '../providers/locations_provider.dart';
import 'location_pick_screen.dart';

/// Matches `LocationsRepository.createLocation`'s exact signature.
/// `imageBytes`, when present, is always the already-normalized JPEG
/// (never the raw picker output) -- see [normalizeLocationPhoto].
typedef CreateLocationCall = Future<void> Function({
  required String title,
  required String description,
  required double latitude,
  required double longitude,
  required String category,
  Uint8List? imageBytes,
  String? requestId,
  String? address,
  List<String>? amenities,
  Map<String, dynamic>? openingHours,
  String? timezone,
});

/// Application-level limits (Phase 2.2A1) -- no corresponding DB column
/// length constraint exists or is being added; kept here purely as UI
/// validation.
const int locationTitleMaxLength = 100;
const int locationDescriptionMaxLength = 1500;

/// `'all'` is a synthetic "no filter" value (see `MapCategoriesSheet`) and
/// is never a real, storable category. `general` is the legacy backend
/// fallback and is deliberately never offered here -- both exclusions
/// come from filtering the single canonical `referenceLocationCategories`
/// list, not a second taxonomy.
List<LocationCategoryDefinition> get _realCategories =>
    referenceLocationCategories.where((c) => c.key != 'all').toList();

/// Full-screen Create Location form (Phase 2.2B: Create Location UX v2).
///
/// [point] is the map coordinate the user already explicitly selected and
/// confirmed in [LocationPickScreen] before this screen was ever pushed
/// -- GPS is never substituted for it. "Змінити" re-opens
/// [LocationPickScreen] for a new explicit selection without losing any
/// other entered field, since this is the same `State` object throughout
/// (nothing is disposed/recreated).
///
/// Pushed via `Navigator.push(MaterialPageRoute(...))` from
/// `_MapScreenState._addLocation` -- matches every other in-feature flow
/// in `map_screen.dart`, none of which use GoRouter (GoRouter here is
/// reserved for the app's four top-level, URL-addressable sections).
///
/// Pops with `true` only after a fully successful create (repository call
/// + `viewportLocationsProvider` invalidation already done). The caller
/// is responsible for showing `locationPendingReviewMessage` on the map's
/// own `Scaffold`, since a `SnackBar` shown here would be torn down by the
/// pop before it could ever be read.
class CreateLocationScreen extends ConsumerStatefulWidget {
  const CreateLocationScreen({
    required this.point,
    @visibleForTesting this.createLocationOverride,
    super.key,
  });

  final LatLng point;

  /// Test-only seam: when set, replaces the real
  /// `LocationsRepository.createLocation` call so a widget test can
  /// control success/failure/timing without constructing a real
  /// `SupabaseClient` (which spins up an isolate and background clients
  /// -- too heavy for a test fixture). Production code never sets this;
  /// see the default in `_submit()`.
  @visibleForTesting
  final CreateLocationCall? createLocationOverride;

  @override
  ConsumerState<CreateLocationScreen> createState() =>
      _CreateLocationScreenState();
}

enum _HoursMode { unspecified, always, scheduled }

class _CreateLocationScreenState extends ConsumerState<CreateLocationScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _imagePicker = ImagePicker();

  String? _titleError;
  Uint8List? _imageBytes;
  String? _imageError;
  bool _isPickingImage = false;
  bool _isSubmitting = false;

  // A safe real category, derived from the canonical collection rather
  // than a hardcoded string.
  late String _category = _realCategories.first.key;

  // The confirmed map point. Mutable (not `widget.point` directly) so
  // "Змінити" can update it in place without recreating this State (and
  // therefore without losing any other entered field).
  late LatLng _point = widget.point;

  List<String> _amenities = [];

  _HoursMode _hoursMode = _HoursMode.unspecified;
  Set<String> _openDays = {'mon', 'tue', 'wed', 'thu', 'fri'};
  TimeOfDay _openTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 18, minute: 0);

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String? get _addressPayload {
    final trimmed = _addressController.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String>? get _amenitiesPayload =>
      _amenities.isEmpty ? null : List.unmodifiable(_amenities);

  static String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic>? get _openingHoursPayload {
    switch (_hoursMode) {
      case _HoursMode.unspecified:
        return null;
      case _HoursMode.always:
        return alwaysOpenSchedule();
      case _HoursMode.scheduled:
        final open = _formatTime(_openTime);
        final close = _formatTime(_closeTime);
        return {
          for (final day in openingHoursDayKeys)
            day: _openDays.contains(day)
                ? [
                    {'open': open, 'close': close}
                  ]
                : closedDaySchedule,
        };
    }
  }

  String? get _timezonePayload =>
      _hoursMode == _HoursMode.unspecified ? null : defaultLocationTimezone;

  Future<void> _changeLocation() async {
    if (_isSubmitting) return;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        fullscreenDialog: true,
        builder: (_) => LocationPickScreen(
          initialTarget: _point,
          initialPicked: _point,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _point = picked);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPickingImage || _isSubmitting) return;
    setState(() {
      _isPickingImage = true;
      _imageError = null;
    });

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (image == null || !mounted) return;
      final pickedBytes = await image.readAsBytes();
      // Normalize before ever storing/previewing: strips EXIF (GPS
      // included -- location_images is a publicly readable bucket),
      // bakes orientation, resizes to the approved long-edge/quality
      // target, and re-encodes as JPEG. This is the only place location
      // photo bytes are produced from here on -- the raw picker output
      // is never kept or uploaded.
      final normalizedBytes = normalizeLocationPhoto(pickedBytes);
      if (!mounted) return;
      setState(() {
        _imageBytes = normalizedBytes;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _imageError = 'Не вдалося вибрати фото.');
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _pickImageSource() async {
    if (_isPickingImage || _isSubmitting) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              key: const Key('create_location_gallery_button'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Галерея'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              key: const Key('create_location_camera_button'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Камера'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ]),
        ),
      ),
    );
    if (source != null) await _pickImage(source);
  }

  Future<void> _openCategorySheet() async {
    if (_isSubmitting) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Категорія',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              _CategoryGrid(
                categories: _realCategories,
                selected: _category,
                enabled: true,
                onSelected: (key) => Navigator.pop(sheetContext, key),
              ),
            ]),
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _category = selected);
    }
  }

  Future<void> _openAmenitiesSheet() async {
    if (_isSubmitting) return;
    var working = Set<String>.from(_amenities);
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Зручності',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                for (final key in locationAmenityKeys)
                  CheckboxListTile(
                    key: Key('create_location_amenity_$key'),
                    value: working.contains(key),
                    title: Text(_amenityLabels[key] ?? key),
                    secondary: Icon(_amenityIcons[key]),
                    onChanged: (checked) => setSheetState(() {
                      if (checked ?? false) {
                        working.add(key);
                      } else {
                        working.remove(key);
                      }
                    }),
                  ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('create_location_amenities_done'),
                    onPressed: () =>
                        Navigator.pop(sheetContext, working.toList()),
                    child: const Text('Готово'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _amenities = result);
    }
  }

  Future<void> _openHoursSheet() async {
    if (_isSubmitting) return;
    var mode = _hoursMode;
    var openDays = Set<String>.from(_openDays);
    var openTime = _openTime;
    var closeTime = _closeTime;

    final result = await showModalBottomSheet<
        ({
          _HoursMode mode,
          Set<String> openDays,
          TimeOfDay open,
          TimeOfDay close
        })>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Години роботи',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                RadioGroup<_HoursMode>(
                  groupValue: mode,
                  onChanged: (value) => setSheetState(() => mode = value!),
                  child: Column(children: [
                    RadioListTile<_HoursMode>(
                      key: const Key('create_location_hours_unspecified'),
                      title: const Text('Не вказано'),
                      value: _HoursMode.unspecified,
                    ),
                    RadioListTile<_HoursMode>(
                      key: const Key('create_location_hours_always'),
                      title: const Text('Цілодобово'),
                      value: _HoursMode.always,
                    ),
                    RadioListTile<_HoursMode>(
                      key: const Key('create_location_hours_scheduled'),
                      title: const Text('За графіком'),
                      value: _HoursMode.scheduled,
                    ),
                  ]),
                ),
                if (mode == _HoursMode.scheduled) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final day in openingHoursDayKeys)
                        FilterChip(
                          key: Key('create_location_hours_day_$day'),
                          label: Text(_dayLabels[day]!),
                          selected: openDays.contains(day),
                          onSelected: (selected) => setSheetState(() {
                            if (selected) {
                              openDays.add(day);
                            } else {
                              openDays.remove(day);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('create_location_hours_open_time'),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: sheetContext,
                              initialTime: openTime,
                              builder: (context, child) => MediaQuery(
                                data: MediaQuery.of(context)
                                    .copyWith(alwaysUse24HourFormat: true),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setSheetState(() => openTime = picked);
                            }
                          },
                          child: Text('Відкриття ${_formatTime(openTime)}'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('create_location_hours_close_time'),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: sheetContext,
                              initialTime: closeTime,
                              builder: (context, child) => MediaQuery(
                                data: MediaQuery.of(context)
                                    .copyWith(alwaysUse24HourFormat: true),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setSheetState(() => closeTime = picked);
                            }
                          },
                          child: Text('Закриття ${_formatTime(closeTime)}'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('create_location_hours_done'),
                    onPressed: () => Navigator.pop(sheetContext, (
                      mode: mode,
                      openDays: openDays,
                      open: openTime,
                      close: closeTime,
                    )),
                    child: const Text('Готово'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _hoursMode = result.mode;
        _openDays = result.openDays;
        _openTime = result.open;
        _closeTime = result.close;
      });
    }
  }

  String get _hoursSummary => switch (_hoursMode) {
        _HoursMode.unspecified => 'Не вказано',
        _HoursMode.always => 'Цілодобово',
        _HoursMode.scheduled => _openDays.isEmpty
            ? 'За графіком'
            : '${_formatTime(_openTime)}-${_formatTime(_closeTime)}',
      };

  String get _amenitiesSummary =>
      _amenities.isEmpty ? 'Не вказано' : _amenities.length.toString();

  /// Guarded by [_isSubmitting] at the very top -- a rapid double tap on
  /// the submit button (or any other re-entrant call) is a no-op on the
  /// second call, so at most one `createLocation()` request is ever sent.
  Future<void> _submit() async {
    if (_isSubmitting) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Введіть назву місця.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _titleError = null;
    });

    final requestId = const Uuid().v4();
    final createLocation = widget.createLocationOverride ??
        ref.read(locationsRepositoryProvider).createLocation;
    try {
      await createLocation(
        title: title,
        description: _descriptionController.text.trim(),
        latitude: _point.latitude,
        longitude: _point.longitude,
        category: _category,
        imageBytes: _imageBytes,
        requestId: requestId,
        address: _addressPayload,
        amenities: _amenitiesPayload,
        openingHours: _openingHoursPayload,
        timezone: _timezonePayload,
      );
      ref.invalidate(viewportLocationsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      // Form state (title/description/category/photo/point/amenities/
      // hours/address) is left exactly as the user entered it -- nothing
      // is cleared on failure.
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не вдалося зберегти локацію. Спробуйте ще раз.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedCategory =
        _realCategories.firstWhere((c) => c.key == _category);
    return Scaffold(
      appBar: AppBar(title: const Text('Нова локація')),
      // resizeToAvoidBottomInset defaults to true -- the Scaffold body is
      // already shrunk by the keyboard height, so MediaQuery.viewInsets
      // is intentionally never added again below (that would double-count
      // it). The focused field scrolls itself into view automatically
      // within the SingleChildScrollView.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Назва', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('create_location_title_field'),
                controller: _titleController,
                autofocus: true,
                enabled: !_isSubmitting,
                textInputAction: TextInputAction.next,
                maxLength: locationTitleMaxLength,
                decoration: InputDecoration(
                  hintText: 'Наприклад, Голосіївський парк',
                  errorText: _titleError,
                ),
                onChanged: (_) {
                  if (_titleError != null) {
                    setState(() => _titleError = null);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Опис', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('create_location_description_field'),
                controller: _descriptionController,
                enabled: !_isSubmitting,
                minLines: 2,
                maxLines: 4,
                maxLength: locationDescriptionMaxLength,
                decoration: const InputDecoration(
                  hintText: 'Коротко опишіть це місце',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Категорія', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _CompactSelectorRow(
                selectorKey: const Key('create_location_category_field'),
                enabled: !_isSubmitting,
                onTap: _openCategorySheet,
                leading: Icon(selectedCategory.icon,
                    color: selectedCategory.referenceColor),
                value: selectedCategory.label,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Фото', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (_imageBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: Image.memory(
                    _imageBytes!,
                    key: const Key('create_location_image_preview'),
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() => _imageBytes = null),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Видалити фото'),
                  ),
                ),
              ] else
                OutlinedButton.icon(
                  key: const Key('create_location_add_photo_button'),
                  onPressed: _isPickingImage || _isSubmitting
                      ? null
                      : _pickImageSource,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Додати фото'),
                ),
              if (_isPickingImage) ...[
                const SizedBox(height: AppSpacing.sm),
                const LinearProgressIndicator(),
              ],
              if (_imageError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_imageError!, style: TextStyle(color: colors.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('Зручності', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _CompactSelectorRow(
                selectorKey: const Key('create_location_amenities_field'),
                enabled: !_isSubmitting,
                onTap: _openAmenitiesSheet,
                value: _amenitiesSummary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Години роботи',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _CompactSelectorRow(
                selectorKey: const Key('create_location_hours_field'),
                enabled: !_isSubmitting,
                onTap: _openHoursSheet,
                value: _hoursSummary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Місце', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _LocationCard(
                point: _point,
                enabled: !_isSubmitting,
                onChange: _changeLocation,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Адреса', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('create_location_address_field'),
                controller: _addressController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  hintText: 'Наприклад, вул. Хрещатик, 1',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('create_location_submit_button'),
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Text('Створити локацію'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _amenityIcons = <String, IconData>{
  'parking': Icons.local_parking,
  'wifi': Icons.wifi,
  'toilet': Icons.wc,
  'accessibility': Icons.accessible,
  'pets': Icons.pets,
  'food': Icons.restaurant,
};

const _amenityLabels = <String, String>{
  'parking': 'Паркінг',
  'wifi': 'Wi-Fi',
  'toilet': 'Туалет',
  'accessibility': 'Доступність',
  'pets': 'З тваринами',
  'food': 'Їжа',
};

const _dayLabels = <String, String>{
  'mon': 'Пн',
  'tue': 'Вт',
  'wed': 'Ср',
  'thu': 'Чт',
  'fri': 'Пт',
  'sat': 'Сб',
  'sun': 'Нд',
};

/// A compact, tappable row for a form field whose real editor lives in a
/// bottom sheet ("Категорія"/"Зручності"/"Години роботи") -- keeps the
/// main form short instead of showing every option permanently.
class _CompactSelectorRow extends StatelessWidget {
  const _CompactSelectorRow({
    required this.value,
    required this.onTap,
    required this.enabled,
    this.leading,
    this.selectorKey,
  });

  final String value;
  final VoidCallback onTap;
  final bool enabled;
  final Widget? leading;
  final Key? selectorKey;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: selectorKey,
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF14231D),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Colors.white)),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final List<LocationCategoryDefinition> categories;
  final String selected;
  final bool enabled;
  final ValueChanged<String> onSelected;

  // Same tile treatment as MapCategoriesSheet, so category presentation
  // stays visually consistent across the app.
  static const _tileBackground = Color(0xFF10221B);
  static const _tileBorder = Color(0xFF294037);

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return GridView.builder(
      key: const Key('create_location_category_grid'),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 7,
        crossAxisSpacing: 7,
        childAspectRatio: textScale > 1.2 ? .82 : .9,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final isSelected = selected == category.key;
        return Semantics(
          button: true,
          selected: isSelected,
          label: category.label.replaceAll('\n', ' '),
          child: InkWell(
            key: Key('create_location_category_${category.key}'),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            onTap: enabled ? () => onSelected(category.key) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: isSelected
                    ? category.referenceColor.withValues(alpha: .30)
                    : _tileBackground,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(
                  color: isSelected ? category.referenceColor : _tileBorder,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(category.icon, size: 22, color: category.referenceColor),
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      category.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        height: 1.05,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFF5F0E6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Read-only coordinates block -- mirrors the small dark info-card
/// language already used for `_RouteEndpoint` in
/// `scalable_locations_screen.dart` (icon + value on a dark rounded
/// card), not a second interactive map. "Змінити" re-opens
/// [LocationPickScreen] for a new explicit selection.
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.point,
    required this.enabled,
    required this.onChange,
  });

  final LatLng point;
  final bool enabled;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('create_location_coordinates_card'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF14231D),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, color: Color(0xFFD4A017)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${point.latitude.toStringAsFixed(5)}, '
              '${point.longitude.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          TextButton(
            key: const Key('create_location_change_location_button'),
            onPressed: enabled ? onChange : null,
            child: const Text('Змінити'),
          ),
        ],
      ),
    );
  }
}
