import 'package:flutter/material.dart';

import '../models/f95_metadata.dart';
import '../models/search_category.dart';
import '../models/search_query.dart';
import '../services/api_service.dart';

typedef FetchPopularTagsCallback = Future<List<PopularTag>> Function({SearchCategory category});

enum _FilterKind { tag, prefix }

class _ActiveFilter {
  final _FilterKind kind;
  final int id;
  final String label;
  bool exclude;

  _ActiveFilter({required this.kind, required this.id, required this.label, this.exclude = false});
}

class _Suggestion {
  final _FilterKind kind;
  final int id;
  final String label;
  final IconData icon;
  final String? trailing;

  const _Suggestion({required this.kind, required this.id, required this.label, required this.icon, this.trailing});
}

/// Omni-search sheet: one field that autocompletes tags, engines, statuses,
/// and creators from the bundled vocabulary. Selected filters become chips
/// (tap to toggle include/exclude, x to remove); leftover text is submitted
/// as the title search. Pops a [SearchQuery].
class SearchOptionsModal extends StatefulWidget {
  final SearchQuery initialQuery;
  final FetchPopularTagsCallback? fetchPopularTags;

  const SearchOptionsModal({super.key, this.initialQuery = const SearchQuery(), this.fetchPopularTags});

  @override
  State<SearchOptionsModal> createState() => _SearchOptionsModalState();
}

class _SearchOptionsModalState extends State<SearchOptionsModal> {
  static const int _maxTagSuggestions = 6;
  static const int _maxPrefixSuggestions = 4;
  static const int _maxPopularTags = 12;

  late final TextEditingController _searchController;
  late SearchCategory _selectedCategory;
  late SortOrder _sort;
  final List<_ActiveFilter> _filters = [];
  String? _creator;
  List<PopularTag> _popularTags = const [];

  static const Map<SearchCategory, IconData> _categoryIcons = {
    SearchCategory.games: Icons.sports_esports_outlined,
    SearchCategory.comics: Icons.menu_book_outlined,
    SearchCategory.animations: Icons.movie_filter_outlined,
    SearchCategory.assets: Icons.layers_outlined,
  };

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    _selectedCategory = query.category;
    _sort = query.sort;
    _searchController = TextEditingController(text: query.search);
    _searchController.addListener(_onTextChanged);
    _creator = query.creator.trim().isEmpty ? null : query.creator.trim();
    _restoreFilters(query);
    _loadPopularTags();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  void _restoreFilters(SearchQuery query) {
    final metadata = F95Metadata.instance;

    void addTags(List<int> ids, bool exclude) {
      for (final id in ids) {
        _filters.add(
          _ActiveFilter(kind: _FilterKind.tag, id: id, label: metadata.tagName(id) ?? '#$id', exclude: exclude),
        );
      }
    }

    void addPrefixes(List<int> ids, bool exclude) {
      for (final id in ids) {
        final name = metadata.prefixById(_selectedCategory, id)?.name ?? '#$id';
        _filters.add(_ActiveFilter(kind: _FilterKind.prefix, id: id, label: name, exclude: exclude));
      }
    }

    addTags(query.tags, false);
    addTags(query.notags, true);
    addPrefixes(query.prefixes, false);
    addPrefixes(query.noprefixes, true);
  }

  Future<void> _loadPopularTags() async {
    final fetch = widget.fetchPopularTags ?? _defaultFetchPopularTags;
    try {
      final tags = await fetch(category: _selectedCategory);
      if (!mounted) return;
      setState(() => _popularTags = tags);
    } catch (_) {
      if (!mounted) return;
      setState(() => _popularTags = const []);
    }
  }

  static Future<List<PopularTag>> _defaultFetchPopularTags({SearchCategory category = SearchCategory.games}) {
    return ApiService.fetchPopularTags(category: category);
  }

  bool _isActive(_FilterKind kind, int id) => _filters.any((f) => f.kind == kind && f.id == id);

  List<_Suggestion> _buildSuggestions(String text) {
    final metadata = F95Metadata.instance;
    final queryText = text.trim().toLowerCase();
    if (queryText.isEmpty) return const [];

    int rank(String name) => name.startsWith(queryText) ? 0 : 1;

    final tagMatches =
        metadata.tagIdsByName.entries
            .where((e) => e.key.contains(queryText) && !_isActive(_FilterKind.tag, e.value))
            .toList()
          ..sort((a, b) {
            final byRank = rank(a.key).compareTo(rank(b.key));
            return byRank != 0 ? byRank : a.key.compareTo(b.key);
          });

    final prefixMatches = metadata
        .prefixesFor(_selectedCategory)
        .where((p) => p.name.toLowerCase().contains(queryText) && !_isActive(_FilterKind.prefix, p.id))
        .toList();

    return [
      for (final entry in tagMatches.take(_maxTagSuggestions))
        _Suggestion(kind: _FilterKind.tag, id: entry.value, label: entry.key, icon: Icons.tag),
      for (final prefix in prefixMatches.take(_maxPrefixSuggestions))
        _Suggestion(
          kind: _FilterKind.prefix,
          id: prefix.id,
          label: prefix.name,
          icon: prefix.isStatus ? Icons.flag_outlined : Icons.memory,
          trailing: prefix.groupName,
        ),
    ];
  }

  void _addFilter(_FilterKind kind, int id, String label) {
    setState(() {
      _filters.add(_ActiveFilter(kind: kind, id: id, label: label));
      _searchController.clear();
    });
  }

  void _setCreatorFromText() {
    setState(() {
      _creator = _searchController.text.trim();
      _searchController.clear();
    });
  }

  void _onCategoryChanged(SearchCategory category) {
    if (category == _selectedCategory) return;
    setState(() {
      _selectedCategory = category;
      // Prefix IDs are category-specific; drop the ones that no longer resolve.
      _filters.removeWhere(
        (f) => f.kind == _FilterKind.prefix && F95Metadata.instance.prefixById(category, f.id) == null,
      );
    });
    _loadPopularTags();
  }

  void _onSubmit() {
    Navigator.of(context).pop(
      SearchQuery(
        category: _selectedCategory,
        search: _searchController.text.trim(),
        creator: _creator ?? '',
        tags: [for (final f in _filters) if (f.kind == _FilterKind.tag && !f.exclude) f.id],
        notags: [for (final f in _filters) if (f.kind == _FilterKind.tag && f.exclude) f.id],
        prefixes: [for (final f in _filters) if (f.kind == _FilterKind.prefix && !f.exclude) f.id],
        noprefixes: [for (final f in _filters) if (f.kind == _FilterKind.prefix && f.exclude) f.id],
        sort: _sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final suggestions = _buildSuggestions(_searchController.text);

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding + keyboardInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_filters.isNotEmpty || _creator != null) ...[
                _buildActiveFilters(colorScheme),
                const SizedBox(height: 12),
              ],
              _buildSearchField(colorScheme),
              if (suggestions.isNotEmpty || _hasCreatorSuggestion) ...[
                const SizedBox(height: 8),
                _buildSuggestionList(colorScheme, suggestions),
              ] else if (_popularSuggestions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Popular tags', style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                _buildPopularTags(colorScheme),
              ],
              const SizedBox(height: 24),
              Text('Category', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildSelectorSurface(colorScheme, _buildCategorySelector(colorScheme)),
              const SizedBox(height: 16),
              Text('Sort by', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              _buildSortSelector(colorScheme),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _onSubmit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                icon: const Icon(Icons.search),
                label: const Text('Search'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasCreatorSuggestion => _searchController.text.trim().isNotEmpty;

  List<PopularTag> get _popularSuggestions {
    final metadata = F95Metadata.instance;
    return _popularTags
        .where((t) => metadata.tagName(t.tagId) != null && !_isActive(_FilterKind.tag, t.tagId))
        .take(_maxPopularTags)
        .toList();
  }

  Widget _buildSearchField(ColorScheme colorScheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _onSubmit(),
        decoration: const InputDecoration(
          hintText: 'Search titles, tags, creators…',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search),
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildActiveFilters(ColorScheme colorScheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in _filters)
          _FilterChipPill(
            label: filter.label,
            exclude: filter.exclude,
            icon: filter.kind == _FilterKind.tag ? Icons.tag : Icons.memory,
            onTap: () => setState(() => filter.exclude = !filter.exclude),
            onRemove: () => setState(() => _filters.remove(filter)),
          ),
        if (_creator != null)
          _FilterChipPill(
            label: 'Creator: $_creator',
            exclude: false,
            icon: Icons.person_outline,
            onTap: () {},
            onRemove: () => setState(() => _creator = null),
          ),
      ],
    );
  }

  Widget _buildSuggestionList(ColorScheme colorScheme, List<_Suggestion> suggestions) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final suggestion in suggestions)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(suggestion.icon, size: 18, color: colorScheme.onSurfaceVariant),
              title: Text(suggestion.label),
              trailing: suggestion.trailing == null
                  ? null
                  : Text(
                      suggestion.trailing!,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
              onTap: () => _addFilter(suggestion.kind, suggestion.id, suggestion.label),
            ),
          if (_hasCreatorSuggestion)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(Icons.person_outline, size: 18, color: colorScheme.onSurfaceVariant),
              title: Text('Creator: "${_searchController.text.trim()}"'),
              onTap: _setCreatorFromText,
            ),
        ],
      ),
    );
  }

  Widget _buildPopularTags(ColorScheme colorScheme) {
    final metadata = F95Metadata.instance;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in _popularSuggestions)
          GestureDetector(
            onTap: () => _addFilter(_FilterKind.tag, tag.tagId, metadata.tagName(tag.tagId)!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.25)),
              ),
              child: Text(metadata.tagName(tag.tagId)!, style: const TextStyle(fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _buildSelectorSurface(ColorScheme colorScheme, Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.28)),
        gradient: LinearGradient(
          colors: [
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }

  Widget _buildCategorySelector(ColorScheme colorScheme) {
    final entries = SearchCategory.values.map((category) {
      final bool isSelected = _selectedCategory == category;
      final icon = _categoryIcons[category]!;

      return Expanded(
        child: Tooltip(
          message: category.displayLabel,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.18)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isSelected ? colorScheme.primary : Colors.transparent, width: 1.5),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _onCategoryChanged(category),
                  child: SizedBox(
                    height: 56,
                    child: Icon(icon, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant, size: 26),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();

    return Row(children: entries);
  }

  Widget _buildSortSelector(ColorScheme colorScheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final order in SortOrder.values)
          GestureDetector(
            onTap: () => setState(() => _sort = order),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _sort == order
                    ? colorScheme.primary.withValues(alpha: 0.18)
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _sort == order ? colorScheme.primary : Colors.transparent, width: 1.5),
              ),
              child: Text(
                order.displayLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: _sort == order ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  fontWeight: _sort == order ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FilterChipPill extends StatelessWidget {
  final String label;
  final bool exclude;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _FilterChipPill({
    required this.label,
    required this.exclude,
    required this.icon,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color accent = exclude ? colorScheme.error : colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(exclude ? Icons.remove : Icons.add, size: 14, color: accent),
            const SizedBox(width: 2),
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 13, color: accent)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close, size: 14, color: accent.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
