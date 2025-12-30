import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/repository/repository.dart';

class SearchAndFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final String searchLabel;
  final String franchisorId;
  final Set<String> selectedFilterIds;
  final Function(String filterId) onFilterSelected;

  const SearchAndFilterBar({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.searchLabel,
    required this.franchisorId,
    required this.selectedFilterIds,
    required this.onFilterSelected,
  });

  @override
  Widget build(BuildContext context) {
    final repository = FranchiseRepository();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            decoration: InputDecoration(
                labelText: searchLabel,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => searchController.clear(),
                      )
                    : null),
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<ProductFilter>>(
            stream: repository.getFiltersStream(franchisorId),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }

              final filters = snapshot.data!;

              return Wrap(
                spacing: 8,
                children: filters.map((filter) {
                  final isSelected = selectedFilterIds.contains(filter.id);

                  return FilterChip(
                    label: Text(filter.name),
                    selected: isSelected,
                    onSelected: (selected) => onFilterSelected(filter.id),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
