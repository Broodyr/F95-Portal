import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/f95_metadata.dart';
import '../models/search_category.dart';
import '../models/search_query.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'app_toast.dart';
import 'segmented_selector.dart';
import 'sliding_reveal.dart';

typedef _EmptyTag = ({int id, String name, bool recent});

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
class SearchOptionsSheet extends StatefulWidget {
  final SearchQuery initialQuery;
  final FetchPopularTagsCallback? fetchPopularTags;

  /// Label of the submit button ('Search' in browse, 'Save' in settings).
  final String submitLabel;

  /// Called with the current query when the sheet is dismissed without an
  /// explicit submit (swipe-down, barrier tap); lets the settings instance
  /// save either way.
  final ValueChanged<SearchQuery>? onDismissSave;

  const SearchOptionsSheet({
    super.key,
    this.initialQuery = const SearchQuery(),
    this.fetchPopularTags,
    this.submitLabel = 'Search',
    this.onDismissSave,
  });

  @override
  State<SearchOptionsSheet> createState() => _SearchOptionsSheetState();
}

class _SearchOptionsSheetState extends State<SearchOptionsSheet> {
  static const int _maxTagSuggestions = 6;
  static const int _maxPrefixSuggestions = 4;
  static const int _maxEmptySuggestions = 32;

  /// Day counts offered by the "Updated within" row; null = anytime.
  static const Map<String, int?> _dateLimits = {'Any': null, '24h': 1, '7d': 7, '30d': 30, '90d': 90, '1y': 365};

  final FocusNode _searchFocus = FocusNode();
  late final TextEditingController _searchController;
  late SearchCategory _selectedCategory;
  late SortOrder _sort;
  int? _dateDays;
  bool _anyTags = false;
  bool _submitted = false;
  final List<_ActiveFilter> _filters = [];
  final Set<String> _expandedSections = {};
  String? _creator;
  String? _title;
  List<PopularTag> _popularTags = const [];
  Map<int, int> _tagCounts = const {};

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    _selectedCategory = query.category;
    _sort = query.sort;
    _dateDays = query.dateDays;
    _anyTags = query.anyTags;
    _searchController = TextEditingController(text: query.search);
    _searchController.addListener(_onTextChanged);
    _searchFocus.addListener(_onTextChanged);
    _creator = query.creator.trim().isEmpty ? null : query.creator.trim();
    _restoreFilters(query);
    // Sections start collapsed, except those carrying restored filters.
    final metadata = F95Metadata.instance;
    for (final filter in _filters) {
      if (filter.kind == _FilterKind.prefix) {
        final group = metadata.prefixById(_selectedCategory, filter.id)?.groupName;
        if (group != null) _expandedSections.add(group);
      }
    }
    _loadPopularTags();
  }

  @override
  void dispose() {
    final dismissSave = widget.onDismissSave;
    if (!_submitted && dismissSave != null) {
      // Deferred: the save notifies listeners, which is not allowed while
      // the tree is being torn down.
      final query = _buildQuery();
      Future.microtask(() => dismissSave(query));
    }
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  /// The sheet is short-lived and reopened fresh, so a plain read (no
  /// listener) of the font-size preference is safe here.
  FontSizeOption get _fontSize => SettingsService.instance.settings.fontSize;

  /// Section headers are anchored: already big enough at titleMedium's 16pt
  /// base, so they hold it (15pt on small) while their contents scale.
  TextStyle? _headerStyle(TextTheme textTheme) => textTheme.titleMedium?.copyWith(fontSize: _fontSize.anchored(16));

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
      setState(() {
        _popularTags = tags;
        _tagCounts = {for (final tag in tags) tag.tagId: tag.count};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _popularTags = const [];
        _tagCounts = const {};
      });
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
        _Suggestion(
          kind: _FilterKind.tag,
          id: entry.value,
          label: entry.key,
          icon: Icons.tag,
          trailing: _tagCounts.containsKey(entry.value) ? NumberFormatter.formatNumber(_tagCounts[entry.value]!) : null,
        ),
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

  int _tagFilterCount({required bool exclude}) =>
      _filters.where((f) => f.kind == _FilterKind.tag && f.exclude == exclude).length;

  void _showTagLimitNotice() {
    AppToast.show(context, 'The API supports at most ${SearchQuery.maxTagsPerDirection} tags per direction.');
  }

  void _addFilter(_FilterKind kind, int id, String label) {
    if (kind == _FilterKind.tag && _tagFilterCount(exclude: false) >= SearchQuery.maxTagsPerDirection) {
      _showTagLimitNotice();
      return;
    }
    setState(() {
      _filters.add(_ActiveFilter(kind: kind, id: id, label: label));
      _searchController.clear();
    });
  }

  void _toggleFilter(_ActiveFilter filter) {
    if (filter.kind == _FilterKind.tag &&
        _tagFilterCount(exclude: !filter.exclude) >= SearchQuery.maxTagsPerDirection) {
      _showTagLimitNotice();
      return;
    }
    setState(() => filter.exclude = !filter.exclude);
  }

  void _setCreatorFromText() {
    setState(() {
      _creator = _searchController.text.trim();
      _searchController.clear();
    });
  }

  void _setTitleFromText() {
    setState(() {
      _title = _searchController.text.trim();
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

  SearchQuery _buildQuery() {
    final leftoverText = _searchController.text.trim();
    return SearchQuery(
      category: _selectedCategory,
      search: _title ?? leftoverText,
      creator: _creator ?? '',
      tags: [
        for (final f in _filters)
          if (f.kind == _FilterKind.tag && !f.exclude) f.id,
      ],
      notags: [
        for (final f in _filters)
          if (f.kind == _FilterKind.tag && f.exclude) f.id,
      ],
      prefixes: [
        for (final f in _filters)
          if (f.kind == _FilterKind.prefix && !f.exclude) f.id,
      ],
      noprefixes: [
        for (final f in _filters)
          if (f.kind == _FilterKind.prefix && f.exclude) f.id,
      ],
      sort: _sort,
      dateDays: _dateDays,
      anyTags: _anyTags,
    );
  }

  void _onSubmit() {
    _submitted = true;
    Navigator.of(context).pop(_buildQuery());
  }

  void _toggleSection(String name) {
    setState(() => _expandedSections.contains(name) ? _expandedSections.remove(name) : _expandedSections.add(name));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final suggestions = _buildSuggestions(_searchController.text);
    final emptyTags = _emptyTagSuggestions();
    final bool showEmptyTags = _searchFocus.hasFocus && _searchController.text.trim().isEmpty && emptyTags.isNotEmpty;

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomPadding + keyboardInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Plain (non-scrollable) grab zone: the sheet's own drag
            // recognizer owns it even when the content below scrolls, so the
            // sheet stays easy to pull down from the top.
            SizedBox(
              key: const Key('sheet-drag-band'),
              height: 44,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_filters.isNotEmpty || _creator != null || _title != null) ...[
                      _buildActiveFilters(colorScheme),
                      const SizedBox(height: 12),
                    ],
                    _buildSearchField(colorScheme),
                    _buildSuggestionDropdown(
                      suggestions.isNotEmpty || _hasCreatorSuggestion || showEmptyTags
                          ? _buildSuggestionList(
                              colorScheme,
                              suggestions,
                              emptyTags: showEmptyTags ? emptyTags : const [],
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text('Category', style: _headerStyle(textTheme)),
                    const SizedBox(height: 8),
                    SegmentedSelector<SearchCategory>(
                      values: SearchCategory.values,
                      isSelected: (category) => _selectedCategory == category,
                      label: (category) => category.displayLabel,
                      onSelect: _onCategoryChanged,
                    ),
                    const SizedBox(height: 8),
                    for (final group in _prefixGroups()) ...[
                      const SizedBox(height: 8),
                      _buildSectionHeader(colorScheme, textTheme, title: group.name, summary: _groupSummary(group)),
                      _buildSectionBody(
                        group.name,
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final prefix in group.prefixes) _buildPrefixPill(colorScheme, prefix)],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('Sort by', style: _headerStyle(textTheme)),
                    const SizedBox(height: 8),
                    SegmentedSelector<SortOrder>(
                      values: SortOrder.values,
                      isSelected: (order) => _sort == order,
                      label: (order) => order.displayLabel,
                      onSelect: (order) => setState(() => _sort = order),
                    ),
                    const SizedBox(height: 16),
                    Text('Updated within', style: _headerStyle(textTheme)),
                    const SizedBox(height: 8),
                    SegmentedSelector<MapEntry<String, int?>>(
                      values: _dateLimits.entries.toList(),
                      isSelected: (entry) => _dateDays == entry.value,
                      label: (entry) => entry.key,
                      onSelect: (entry) => setState(() => _dateDays = entry.value),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _onSubmit,
                      style: FilledButton.styleFrom(
                        // Tighter padding offsets the bigger CTA label so
                        // the button height stays put.
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.secondary,
                        textStyle: AppButtons.ctaTextStyle,
                      ),
                      icon: const Icon(Icons.search, size: AppButtons.ctaIconSize),
                      label: Text(widget.submitLabel),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Collapsible section header: title left, current-value summary and a
  /// chevron right. Sections start collapsed to keep the sheet compact.
  Widget _buildSectionHeader(
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required String title,
    required String summary,
  }) {
    final bool expanded = _expandedSections.contains(title);
    return InkWell(
      onTap: () => _toggleSection(title),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(title, style: _headerStyle(textTheme)),
            const Spacer(),
            if (summary.isNotEmpty) Text(summary, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: Motion.duration,
              curve: Motion.curve,
              child: Icon(Icons.expand_more, size: 20, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// Suggestion dropdown that slides open/closed under the search field.
  /// [list] is null when nothing should show; [SlidingReveal] retains the
  /// outgoing list through the slide-shut.
  Widget _buildSuggestionDropdown(Widget? list) {
    return SlidingReveal(
      key: const Key('suggestion-dropdown'),
      visible: list != null,
      child: list == null ? null : Padding(padding: const EdgeInsets.only(top: 8), child: list),
    );
  }

  /// Section body that slides open/closed, matching the segmented
  /// selectors' feel. Collapsed bodies are unmounted (not just zero-height)
  /// so hidden pills can't be found or hit.
  Widget _buildSectionBody(String name, Widget child) {
    return SlidingReveal(
      key: Key('section-body-$name'),
      visible: _expandedSections.contains(name),
      child: Padding(padding: const EdgeInsets.only(top: 4), child: child),
    );
  }

  /// Active-filter summary for a collapsed prefix group ("2 active").
  String _groupSummary(({String name, List<F95Prefix> prefixes}) group) {
    final ids = {for (final prefix in group.prefixes) prefix.id};
    final count = _filters.where((f) => f.kind == _FilterKind.prefix && ids.contains(f.id)).length;
    return count == 0 ? '' : '$count active';
  }

  bool get _hasCreatorSuggestion => _searchController.text.trim().isNotEmpty;

  /// What to suggest while the field is empty: the user's recently used
  /// tags first, then popular tags for the category filling the remaining
  /// slots. New users see pure discovery; active users see mostly their
  /// own history.
  ///
  /// Possible future change: sample the popular portion from a deeper
  /// slice of the ranking (e.g. a random 8 of the top 40) so it varies
  /// between opens instead of always showing the same site-wide top tags.
  List<_EmptyTag> _emptyTagSuggestions() {
    final metadata = F95Metadata.instance;
    final settings = SettingsService.instance.settings;

    final suggestions = <_EmptyTag>[];
    final seen = <int>{};

    void add(int id, {required bool recent}) {
      if (suggestions.length >= _maxEmptySuggestions) return;
      final name = metadata.tagName(id);
      if (name == null || _isActive(_FilterKind.tag, id) || !seen.add(id)) return;
      suggestions.add((id: id, name: name, recent: recent));
    }

    for (final id in settings.recentTags) {
      add(id, recent: true);
    }
    for (final tag in _popularTags) {
      add(tag.tagId, recent: false);
    }
    return suggestions;
  }

  Widget _buildSearchField(ColorScheme colorScheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.onSurface.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _onSubmit(),
        // Anchored: the field is already comfortable at its 16pt base.
        style: TextStyle(fontSize: _fontSize.anchored(16)),
        decoration: InputDecoration(
          hintText: 'Search titles, tags, creators…',
          hintStyle: TextStyle(color: AppColors.of(context).hintText, fontSize: _fontSize.anchored(16)),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildActiveFilters(ColorScheme colorScheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Prefix filters are not chips here — they live in the always-visible
        // Engine/Other/Status pill sections below.
        for (final filter in _filters)
          if (filter.kind == _FilterKind.tag)
            _FilterChipPill(
              label: filter.label,
              exclude: filter.exclude,
              icon: Icons.tag,
              onTap: () => _toggleFilter(filter),
              onRemove: () => setState(() => _filters.remove(filter)),
            ),
        if (_title != null)
          _FilterChipPill(
            label: 'Title: $_title',
            exclude: false,
            icon: Icons.search,
            onTap: () {},
            onRemove: () => setState(() => _title = null),
          ),
        if (_creator != null)
          _FilterChipPill(
            label: 'Creator: $_creator',
            exclude: false,
            icon: Icons.person_outline,
            onTap: () {},
            onRemove: () => setState(() => _creator = null),
          ),
        if (_tagFilterCount(exclude: false) >= 2)
          GestureDetector(
            onTap: () => setState(() => _anyTags = !_anyTags),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: AppAlphas.chipFill),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_anyTags ? Icons.join_full : Icons.join_inner, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    _anyTags ? 'Match: any' : 'Match: all',
                    style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSuggestionList(
    ColorScheme colorScheme,
    List<_Suggestion> suggestions, {
    List<_EmptyTag> emptyTags = const [],
  }) {
    // A Material (not a decorated Container): ListTile paints its ink on
    // the nearest Material, and newer SDKs assert when a colored
    // DecoratedBox would hide it.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: AppAlphas.chipFill),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.onSurface.withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
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
                    : Text(suggestion.trailing!, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                onTap: () => _addFilter(suggestion.kind, suggestion.id, suggestion.label),
              ),
            if (_hasCreatorSuggestion) ...[
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(Icons.search, size: 18, color: colorScheme.onSurfaceVariant),
                title: Text('Title: "${_searchController.text.trim()}"'),
                onTap: _setTitleFromText,
              ),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(Icons.person_outline, size: 18, color: colorScheme.onSurfaceVariant),
                title: Text('Creator: "${_searchController.text.trim()}"'),
                onTap: _setCreatorFromText,
              ),
            ],
            if (emptyTags.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Suggestions', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final tag in emptyTags) _buildEmptyTagChip(colorScheme, tag)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact tap-to-add chip for the empty-field suggestion cloud; recents
  /// carry a history icon, the popular fill a trending one.
  Widget _buildEmptyTagChip(ColorScheme colorScheme, _EmptyTag tag) {
    return GestureDetector(
      onTap: () => _addFilter(_FilterKind.tag, tag.id, tag.name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: AppAlphas.chipFill),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tag.recent ? Icons.history : Icons.trending_up, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(tag.name, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  /// Prefix groups for the selected category, Engine first, Status last,
  /// anything between them alphabetical,
  /// preserving the vocabulary's own group names.
  List<({String name, List<F95Prefix> prefixes})> _prefixGroups() {
    final grouped = <int, ({String name, List<F95Prefix> prefixes})>{};
    for (final prefix in F95Metadata.instance.prefixesFor(_selectedCategory)) {
      grouped.putIfAbsent(prefix.groupId, () => (name: prefix.groupName, prefixes: [])).prefixes.add(prefix);
    }
    final groups = grouped.values.toList();
    groups.sort((a, b) {
      int rank(({String name, List<F95Prefix> prefixes}) g) {
        if (g.name == 'Engine') return 0;
        if (g.prefixes.any((p) => p.isStatus)) return 2;
        return 1;
      }

      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.name.compareTo(b.name);
    });
    return groups;
  }

  _ActiveFilter? _prefixFilter(int id) {
    for (final filter in _filters) {
      if (filter.kind == _FilterKind.prefix && filter.id == id) return filter;
    }
    return null;
  }

  /// Tri-state pill: tap cycles off -> include -> exclude -> off.
  Widget _buildPrefixPill(ColorScheme colorScheme, F95Prefix prefix) {
    final filter = _prefixFilter(prefix.id);
    final bool include = filter != null && !filter.exclude;
    final bool exclude = filter != null && filter.exclude;
    final Color accent = exclude ? colorScheme.error : colorScheme.primary;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (filter == null) {
            _filters.add(_ActiveFilter(kind: _FilterKind.prefix, id: prefix.id, label: prefix.name));
          } else if (!filter.exclude) {
            filter.exclude = true;
          } else {
            _filters.remove(filter);
          }
        });
      },
      child: AnimatedContainer(
        duration: Motion.duration,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: filter == null ? Colors.black.withValues(alpha: AppAlphas.chipFill) : accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: filter == null ? Colors.transparent : accent, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (include) ...[const Icon(Icons.add, size: 14, color: Colors.white), const SizedBox(width: 3)],
            if (exclude) ...[const Icon(Icons.remove, size: 14, color: Colors.white), const SizedBox(width: 3)],
            Text(
              prefix.name,
              style: TextStyle(
                fontSize: 13,
                color: filter == null ? colorScheme.onSurfaceVariant : accent,
                fontWeight: filter == null ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 2, 0, 2),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The include/exclude state is the most important bit of the chip,
            // so render it white and heavy rather than in the accent tint.
            Icon(exclude ? Icons.remove : Icons.add, size: 18, color: Colors.white, weight: 700),
            const SizedBox(width: 3),
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: accent, fontWeight: FontWeight.w500),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                child: Icon(Icons.close, size: 16, color: accent.withValues(alpha: 0.8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
