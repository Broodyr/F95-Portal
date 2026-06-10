import 'package:flutter/material.dart';

import '../models/search_category.dart';

class SearchOptionsResult {
  final String query;
  final SearchCategory category;

  const SearchOptionsResult({required this.query, required this.category});
}

class SearchOptionsModal extends StatefulWidget {
  final String initialQuery;
  final SearchCategory initialCategory;

  const SearchOptionsModal({super.key, this.initialQuery = '', this.initialCategory = SearchCategory.games});

  @override
  State<SearchOptionsModal> createState() => _SearchOptionsModalState();
}

class _SearchOptionsModalState extends State<SearchOptionsModal> {
  late final TextEditingController _searchController;
  late SearchCategory _selectedCategory;

  static const Map<SearchCategory, IconData> _categoryIcons = {
    SearchCategory.games: Icons.sports_esports_outlined,
    SearchCategory.comics: Icons.menu_book_outlined,
    SearchCategory.animations: Icons.movie_filter_outlined,
    SearchCategory.assets: Icons.layers_outlined,
    SearchCategory.mods: Icons.extension_outlined,
  };

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _searchController = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding + keyboardInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchField(colorScheme),
            const SizedBox(height: 24),
            Text('Category', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            DecoratedBox(
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
              child: Padding(padding: const EdgeInsets.all(12), child: _buildCategorySelector(colorScheme)),
            ),
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
    );
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
          hintText: 'Search by title, tag, or creator.',
          border: InputBorder.none,
          prefixIcon: Icon(Icons.search),
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
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
                  onTap: () => setState(() => _selectedCategory = category),
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

  void _onSubmit() {
    Navigator.of(context).pop(SearchOptionsResult(query: _searchController.text.trim(), category: _selectedCategory));
  }
}
