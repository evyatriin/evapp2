import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'vehicle_model.dart';
import 'vehicle_provider.dart';
import 'vehicle_template_model.dart';
import '../authentication/user_provider.dart';

class VehicleSelectionScreen extends ConsumerStatefulWidget {
  const VehicleSelectionScreen({super.key});

  @override
  ConsumerState<VehicleSelectionScreen> createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends ConsumerState<VehicleSelectionScreen> {
  String _selectedFilter = 'All';
  VehicleTemplate? _selectedTemplate;
  bool _isAdding = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(vehicleTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add new vehicle'),
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.green,
            child: BackButton(color: Colors.white),
          ),
        ),
      ),
      body: templatesAsync.when(
        data: (templates) {
          final brands = ['All', ...templates.map((t) => t.brand).toSet().toList()];
          final filteredTemplates = _selectedFilter == 'All'
              ? templates
              : templates.where((t) => t.brand == _selectedFilter).toList();

          return Column(
            children: [
              // Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  children: brands.map((brand) {
                    final isSelected = _selectedFilter == brand;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(brand),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() => _selectedFilter = brand);
                        },
                        backgroundColor: Colors.white,
                        selectedColor: Colors.green,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: Colors.grey.shade300),
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
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: filteredTemplates.length,
                  itemBuilder: (context, index) {
                    final template = filteredTemplates[index];
                    final isSelected = _selectedTemplate?.id == template.id;

                    return InkWell(
                      onTap: () => setState(() => _selectedTemplate = template),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.green.withOpacity(0.2) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? Colors.green : Colors.grey.shade200,
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
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.directions_car, size: 48, color: Colors.grey),
                                ),
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
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _selectedTemplate == null || _isAdding
                        ? null
                        : () => _addVehicle(context, _selectedTemplate!),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    ),
                    child: _isAdding
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Add This Vehicle',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  Future<void> _addVehicle(BuildContext context, VehicleTemplate template) async {
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

    await ref.read(vehicleProvider.notifier).addVehicle(vehicle);

    if (mounted) {
      setState(() => _isAdding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle Added Successfully!')),
      );
      
      // Check if we are in onboarding flow or normal app flow
      // If in onboarding, we pop to return to the OnboardingScreen which has moved to the Location step
      context.pop();
    }
  }
}
