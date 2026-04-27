import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'vehicle_model.dart';
import 'vehicle_provider.dart';
import 'vehicle_template_model.dart';
import '../authentication/user_provider.dart';

class VehicleSelectionScreen extends ConsumerStatefulWidget {
  const VehicleSelectionScreen({super.key});

  @override
  ConsumerState<VehicleSelectionScreen> createState() =>
      _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState
    extends ConsumerState<VehicleSelectionScreen> {
  String _selectedFilter = 'All';
  VehicleTemplate? _selectedTemplate;
  bool _isAdding = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(vehicleTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add new vehicle'),
      ),
      body: templatesAsync.when(
        data: (templates) {
          final brands = ['All', ...templates.map((t) => t.brand).toSet()];
          final query = _searchController.text.trim().toLowerCase();
          final filteredTemplates =
              _selectedFilter == 'All'
                  ? templates
                  : templates.where((t) => t.brand == _selectedFilter).toList();
          final visibleTemplates =
              query.isEmpty
                  ? filteredTemplates
                  : filteredTemplates.where((t) {
                    final haystack =
                        '${t.brand} ${t.model} ${t.variant}'.toLowerCase();
                    return haystack.contains(query);
                  }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search brand or model',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              // Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children:
                      brands.map((brand) {
                        final isSelected = _selectedFilter == brand;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(brand),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() => _selectedFilter = brand);
                            },
                            selectedColor: theme.colorScheme.primary,
                            labelStyle: TextStyle(
                              color:
                                  isSelected
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: theme.colorScheme.outlineVariant),
                            ),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                ),
              ),

              // Grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.84,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: visibleTemplates.length,
                  itemBuilder: (context, index) {
                    final template = visibleTemplates[index];
                    final isSelected = _selectedTemplate?.id == template.id;

                    return InkWell(
                      onTap: () => setState(() => _selectedTemplate = template),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Image.network(
                                  template.imageUrl,
                                  fit: BoxFit.contain,
                                  cacheWidth: 400,
                                  loadingBuilder: (
                                    context,
                                    child,
                                    loadingProgress,
                                  ) {
                                    if (loadingProgress == null) return child;
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    );
                                  },
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          const Icon(
                                            Icons.directions_car,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                template.variant,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Text(
                                '${template.brand} ${template.model}',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Add Button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed:
                        _selectedTemplate == null || _isAdding
                            ? null
                            : () => _addVehicle(context, _selectedTemplate!),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child:
                        _isAdding
                            ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                            : const Text(
                              'Add This Vehicle',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Future<void> _addVehicle(
    BuildContext context,
    VehicleTemplate template,
  ) async {
    setState(() => _isAdding = true);

    final userId = ref.read(userProvider)?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to add vehicle')),
      );
      setState(() => _isAdding = false);
      return;
    }

    final vehicle = VehicleProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userId,
      brand: template.brand,
      model: template.model,
      variant: template.variant,
      rangeEfficiency: template.rangeEfficiency,
      imageUrl: template.imageUrl,
      preferredChargingNetworks: template.preferredChargingNetworks,
    );
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    if (!mounted) return;

    try {
      final addedVehicle = await ref.read(vehicleProvider.notifier).addVehicle(
        vehicle,
      );

      if (!mounted) return;

      setState(() => _isAdding = false);

      if (addedVehicle == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not save vehicle. Please try again.'),
          ),
        );
        return;
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('Vehicle added successfully.')),
      );
      router.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAdding = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save vehicle: $e')),
      );
    }
  }
}
