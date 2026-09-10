import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          leading: const BackButton(),
          titleSpacing: 0,
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
          actions: const [SizedBox(width: 12)],
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

  Widget _initialState() => ListView(
        key: const ValueKey('search_initial'),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: [
          const TravelSectionHeader(title: 'Популярні категорії'),
          const SizedBox(height: 8),
          _categoryChips(),
        ],
      );

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
