import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/location_categories.dart';
import '../domain/location_model.dart';
import '../domain/location_query.dart';
import '../providers/locations_provider.dart';
import '../../social/providers/public_profile_provider.dart';
import 'location_card.dart';
import 'map_screen.dart';

typedef SearchPageLoader = Future<LocationPage> Function({
  LocationCursor? cursor,
  String? category,
  String? search,
  required int limit,
});

class LocationSearchScreen extends ConsumerStatefulWidget {
  const LocationSearchScreen({
    this.pageLoader,
    this.onLocationTap,
    this.savedLocationIds,
    super.key,
  });

  final SearchPageLoader? pageLoader;
  final ValueChanged<LocationModel>? onLocationTap;
  final Set<String>? savedLocationIds;

  @override
  ConsumerState<LocationSearchScreen> createState() =>
      _LocationSearchScreenState();
}

class _LocationSearchScreenState extends ConsumerState<LocationSearchScreen> {
  static const _pageSize = 20;
  static const _debounceDuration = Duration(milliseconds: 350);
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _items = <LocationQueryItem>[];
  Timer? _debounce;
  LocationCursor? _cursor;
  String _query = '';
  String _category = 'all';
  bool _loading = false;
  bool _hasMore = false;
  Object? _error;

  bool get _hasSearch => _query.isNotEmpty || _category != 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final next = value.trim();
    setState(() => _query = next);
    if (next.isEmpty && _category == 'all') {
      setState(() {
        _items.clear();
        _error = null;
        _hasMore = false;
      });
      return;
    }
    _debounce = Timer(_debounceDuration, () => _load(reset: true));
  }

  Future<void> _selectCategory(String category) async {
    _debounce?.cancel();
    setState(() => _category = category);
    if (!_hasSearch) {
      setState(() {
        _items.clear();
        _error = null;
      });
      return;
    }
    await _load(reset: true);
  }

  /// Search Phase 2B — puts [term] into the search field and runs it
  /// immediately (no debounce: this is already a committed action, either
  /// a Recent row or a text-only Popular shortcut).
  void _applyQuery(String term) {
    _debounce?.cancel();
    _controller.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    setState(() => _query = term);
    _load(reset: true);
  }

  /// Search Phase 2B — a Popular row either applies its mapped canonical
  /// category (see `_popularEntries`) through the existing category
  /// contract, or, when no clean mapping exists, runs as a real text
  /// search for its own label.
  void _applyPopular(_PopularEntry entry) {
    if (entry.category != null) {
      _selectCategory(entry.category!);
    } else {
      _applyQuery(entry.label);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && !_hasMore) || !_hasSearch) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _cursor = null;
      }
    });
    try {
      final loader = widget.pageLoader ??
          ({cursor, category, search, required limit}) =>
              ref.read(locationsRepositoryProvider).fetchDiscoverPage(
                    cursor: cursor,
                    category: category,
                    search: search,
                    limit: limit,
                  );
      final page = await loader(
        cursor: reset ? null : _cursor,
        category: _category == 'all' ? null : _category,
        search: _query.isEmpty ? null : _query,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        final existing = _items.map((item) => item.location.id).toSet();
        _items
            .addAll(page.items.where((item) => existing.add(item.location.id)));
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
      // Search Phase 2B — a term becomes "recent" only once a non-empty
      // debounced search successfully completes (not on every keystroke,
      // not on load-more pagination, not on category-only shortcuts).
      if (reset && _query.isNotEmpty) {
        unawaited(ref.read(recentSearchesProvider.notifier).record(_query));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final effectiveScale =
        mediaQuery.textScaler.scale(1).clamp(1.0, 1.12).toDouble();
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          automaticallyImplyLeading: false,
          titleSpacing: 12,
          title: TravelSearchField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onQueryChanged,
            onClear: () {
              _controller.clear();
              _onQueryChanged('');
              _focusNode.requestFocus();
            },
          ),
          actions: [
            TextButton(
              key: const Key('search_cancel_action'),
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD4A017),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Скасувати', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: !_hasSearch ? _initialState() : _resultsState(),
          ),
        ),
      ),
    );
  }

  Widget _initialState() {
    // Search Phase 2B — the master reference's Screen 6 initial state shows
    // no category chips, only "Недавні запити" (real per-device history,
    // hidden entirely when empty -- never fabricated) and "Популярні"
    // (curated, static shortcuts; see `_popularEntries`).
    final recent = ref.watch(recentSearchesProvider).value ?? const <String>[];
    return ListView(
      key: const ValueKey('search_initial'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        if (recent.isNotEmpty) ...[
          const TravelSectionHeader(title: 'Недавні запити'),
          const SizedBox(height: 4),
          ...recent.map((term) => _SearchShortcutRow(
                key: Key('recent_row_$term'),
                icon: Icons.history_rounded,
                label: term,
                onTap: () => _applyQuery(term),
              )),
          const SizedBox(height: 18),
        ],
        const TravelSectionHeader(title: 'Популярні'),
        const SizedBox(height: 4),
        ..._popularEntries.map((entry) => _SearchShortcutRow(
              key: Key('popular_row_${entry.label}'),
              icon: entry.icon,
              label: entry.label,
              onTap: () => _applyPopular(entry),
            )),
      ],
    );
  }

  Widget _resultsState() => Column(
        key: const ValueKey('search_results'),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: _categoryChips(),
          ),
          if (_loading && _items.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _resultContent()),
        ],
      );

  Widget _resultContent() {
    if (_loading && _items.isEmpty) {
      return const Center(
        key: Key('search_loading'),
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (_error != null && _items.isEmpty) {
      return TravelEmptyState(
        key: const Key('search_error'),
        icon: Icons.wifi_off_rounded,
        title: 'Не вдалося виконати пошук',
        actionLabel: 'Спробувати ще раз',
        onAction: () => _load(reset: true),
      );
    }
    if (_items.isEmpty) {
      return const TravelEmptyState(
        key: Key('search_empty'),
        icon: Icons.search_off_rounded,
        title: 'Нічого не знайдено',
        message: 'Спробуйте іншу назву або категорію.',
      );
    }
    return ListView.builder(
      key: const Key('search_result_list'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.tonal(
              key: const Key('search_load_more'),
              onPressed: _loading ? null : () => _load(reset: false),
              child: const Text('Показати ще'),
            ),
          );
        }
        return _SearchResultCard(
          item: _items[index],
          onLocationTap: widget.onLocationTap,
          savedLocationIds: widget.savedLocationIds,
        );
      },
    );
  }

  Widget _categoryChips() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: locationCategoryPresentations.entries
            .where((entry) => entry.key != 'general')
            .map((entry) => ChoiceChip(
                  key: Key('search_category_${entry.key}'),
                  avatar: Icon(entry.value.icon, size: 14),
                  label: Text(entry.value.label,
                      style: const TextStyle(fontSize: 12)),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  visualDensity: const VisualDensity(vertical: -3),
                  selected: _category == entry.key,
                  onSelected: (_) => _selectCategory(entry.key),
                ))
            .toList(growable: false),
      );
}

class _SearchResultCard extends ConsumerWidget {
  const _SearchResultCard({
    required this.item,
    this.onLocationTap,
    this.savedLocationIds,
  });

  final LocationQueryItem item;
  final ValueChanged<LocationModel>? onLocationTap;
  final Set<String>? savedLocationIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = savedLocationIds ??
        ref.watch(savedPublicLocationsProvider).value ??
        const <String>{};
    return LocationCard(
      location: item.location,
      compact: true,
      distanceMeters: item.distanceMeters,
      isSaved: saved.contains(item.location.id),
      onBookmarkTap: savedLocationIds != null
          ? null
          : () => ref
              .read(savedPublicLocationsProvider.notifier)
              .toggle(item.location.id),
      onTap: () {
        if (onLocationTap != null) {
          onLocationTap!(item.location);
          return;
        }
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => LocationDetailsScreen(location: item.location),
        ));
      },
    );
  }
}

class TravelSearchField extends StatelessWidget {
  const TravelSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SizedBox(
          height: 38,
          child: TextField(
            key: const Key('travel_search_field'),
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Пошук місць',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Очистити',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      constraints: const BoxConstraints(minWidth: 36),
                      padding: EdgeInsets.zero,
                    ),
              filled: true,
              fillColor: const Color(0xFF14231D),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: Color(0xFFD4A017)),
              ),
            ),
          ),
        ),
      );
}

class TravelSectionHeader extends StatelessWidget {
  const TravelSectionHeader({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
      );
}

class TravelEmptyState extends StatelessWidget {
  const TravelEmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: const Color(0xFFD4A017)),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                  onPressed: onAction, child: Text(actionLabel!)),
            ],
          ]),
        ),
      );
}

/// Search Phase 2B — a single "Недавні запити"/"Популярні" row: a compact
/// gold/accent leading icon plus plain text, matching the master
/// reference's Screen 6 initial state (`qa/master/master_reference_board.png`).
class _SearchShortcutRow extends StatelessWidget {
  const _SearchShortcutRow({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFFD4A017)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
}

class _PopularEntry {
  const _PopularEntry(this.label, this.icon, {this.category});
  final String label;
  final IconData icon;

  /// A canonical key from [referenceLocationCategories], or null when no
  /// clean mapping exists (in which case the row runs [label] itself as a
  /// real text search instead).
  final String? category;
}

/// Search Phase 2B — curated Popular shortcuts for Screen 6. There is no
/// backend for trending search terms, so this is a static, product-curated
/// list (never labeled as live/dynamic data). Mapping chosen by auditing
/// `referenceLocationCategories` (lib/features/map/domain/location_categories.dart):
///   Парки                 -> category 'nature'      (Природа; Icons.park)
///   Музеї                 -> category 'culture'      (Культура; Icons.account_balance)
///   Кав'ярні               -> category 'cafe'         (Кафе; Icons.local_cafe)
///   Ресторани              -> no canonical category   -> real text search "Ресторани"
///   Оглядові майданчики    -> category 'viewpoints'   (Оглядові місця; Icons.photo_camera)
const _popularEntries = <_PopularEntry>[
  _PopularEntry('Парки', Icons.park, category: 'nature'),
  _PopularEntry('Музеї', Icons.account_balance, category: 'culture'),
  _PopularEntry("Кав'ярні", Icons.local_cafe, category: 'cafe'),
  _PopularEntry('Ресторани', Icons.restaurant),
  _PopularEntry('Оглядові майданчики', Icons.photo_camera,
      category: 'viewpoints'),
];

/// Search Phase 2B — REAL per-device Recent Searches (SharedPreferences),
/// following the same pattern as [SavedPublicLocationsNotifier] in
/// `public_profile_provider.dart`: a per-user key with an anonymous
/// fallback. A term is recorded only when a non-empty debounced search
/// successfully completes (see `_load` in [_LocationSearchScreenState]) --
/// never on every keystroke, and never for category-only shortcuts. This
/// keeps the save rule deterministic and testable: history reflects
/// committed searches, not typing noise.
class RecentSearchesNotifier extends AsyncNotifier<List<String>> {
  static const maxEntries = 5;
  late SharedPreferences _preferences;
  late String _key;

  @override
  Future<List<String>> build() async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    _key = 'recent_searches_v1_$userId';
    _preferences = await SharedPreferences.getInstance();
    return _preferences.getStringList(_key) ?? const [];
  }

  Future<void> record(String term) async {
    // Recent history is a nice-to-have, not the search path itself: if
    // build() never reached AsyncData (e.g. still loading, or failed --
    // as happens in widget tests that don't initialize Supabase), skip
    // silently rather than touching the not-yet-assigned `_preferences`.
    if (state is! AsyncData<List<String>>) return;
    final current = state.value ?? const <String>[];
    final updated = mergeRecent(current, term);
    if (identical(updated, current)) return;
    state = AsyncData(updated);
    await _preferences.setStringList(_key, updated);
  }

  /// The deterministic Recent-history contract (Search Phase 2B): trim
  /// whitespace, ignore empty values, dedupe case-insensitively (newest
  /// occurrence wins and moves to front), newest first, bounded to
  /// [maxEntries]. Pure and Riverpod/Supabase-free so it is directly
  /// unit-testable. Returns [current] unchanged (same instance) when
  /// [term] is blank.
  @visibleForTesting
  static List<String> mergeRecent(List<String> current, String term,
      {int maxEntries = RecentSearchesNotifier.maxEntries}) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return current;
    return [
      trimmed,
      ...current
          .where((existing) => existing.toLowerCase() != trimmed.toLowerCase()),
    ].take(maxEntries).toList(growable: false);
  }
}

final recentSearchesProvider =
    AsyncNotifierProvider<RecentSearchesNotifier, List<String>>(
  RecentSearchesNotifier.new,
);
