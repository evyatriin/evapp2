import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'vehicle_model.dart';
import 'vehicle_provider.dart';
import 'vehicle_photo_service.dart';
import 'vehicle_template_model.dart';
import '../authentication/user_provider.dart';
import '../../common_widgets/app_button.dart';
import '../../common_widgets/app_card.dart';

class VehicleFormScreen extends ConsumerStatefulWidget {
  final VehicleProfile? vehicleToEdit;

  const VehicleFormScreen({super.key, this.vehicleToEdit});

  @override
  ConsumerState<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends ConsumerState<VehicleFormScreen> {
  late String _brand;
  late String _model;
  late String _variant;
  late double _rangeEfficiency;
  String? _imageUrl;
  String? _photoUrl;
  File? _photoFile;
  List<String> _selectedNetworks = [];
  bool _isUploading = false;

  final List<String> _availableNetworks = [
    'Tesla Supercharger',
    'Tata Power',
    'Ather Grid',
    'Jio-bp',
    'Fortum',
    'Statiq',
    'ChargeZone',
  ];

  @override
  void initState() {
    super.initState();
    final v = widget.vehicleToEdit;
    _brand = v?.brand ?? 'Tata';
    _model = v?.model ?? 'Nexon EV';
    _variant = v?.variant ?? 'Max';
    _rangeEfficiency = v?.rangeEfficiency ?? 0.8;
    _imageUrl = v?.imageUrl;
    _photoUrl = v?.photoUrl;
    _selectedNetworks = v?.preferredChargingNetworks.toList() ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.vehicleToEdit != null;
    final templatesAsync = ref.watch(vehicleTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Vehicle' : 'Add Vehicle'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              children: [
                Icon(
                  PhosphorIcons.carProfile(PhosphorIconsStyle.duotone),
                  size: 52,
                  color: theme.colorScheme.primary,
                ),
                const Gap(12),
                Text(
                  'Vehicle basics',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Gap(14),
                templatesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => _buildBasicTextFields(),
                  data: (templates) => _buildTemplateDropdowns(templates),
                ),
              ],
            ),
          ),
          const Gap(14),
          AppCard(child: _buildImagePicker(theme)),
          const Gap(14),
          AppCard(child: _buildPhotoPicker(theme)),
          const Gap(14),
          AppCard(child: _buildChargingNetworkSelector(theme)),
          const Gap(14),
          Text('Range estimate', style: theme.textTheme.titleMedium),
          const Gap(8),
          AppCard(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Efficiency'),
                    Text(
                      '${(_rangeEfficiency * 100).toInt()}%',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _rangeEfficiency,
                  min: 0.5,
                  max: 1.0,
                  divisions: 10,
                  label: '${(_rangeEfficiency * 100).toInt()}%',
                  onChanged: (val) => setState(() => _rangeEfficiency = val),
                ),
                const Divider(),
                const Gap(8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Estimated Range'),
                    Text(
                      '${(ratedRangeKmFor(_brand, _model) * _rangeEfficiency).toInt()} km',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.tertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Based on ${ratedRangeKmFor(_brand, _model).toInt()} km rated range × ${(_rangeEfficiency * 100).toInt()}% efficiency.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(20),
          AppButton(
            label: 'Save Vehicle',
            icon: Icons.save,
            onPressed: _saveVehicle,
            isFullWidth: true,
          ),
        ],
      ),
    );
  }

  /// Cascading dropdowns sourced from vehicleTemplatesProvider.
  /// Brand → Model → Variant. Updates rangeEfficiency from template on change.
  Widget _buildTemplateDropdowns(List<VehicleTemplate> templates) {
    final brands = templates.map((t) => t.brand).toSet().toList()..sort();
    if (!brands.contains(_brand) && brands.isNotEmpty) {
      _brand = brands.first;
    }

    final models = templates
        .where((t) => t.brand == _brand)
        .map((t) => t.model)
        .toSet()
        .toList()
      ..sort();
    if (!models.contains(_model) && models.isNotEmpty) {
      _model = models.first;
    }

    final variants = templates
        .where((t) => t.brand == _brand && t.model == _model)
        .map((t) => t.variant)
        .toSet()
        .toList()
      ..sort();
    if (!variants.contains(_variant) && variants.isNotEmpty) {
      _variant = variants.first;
    }

    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _brand,
          decoration: const InputDecoration(
            labelText: 'Brand',
            border: OutlineInputBorder(),
          ),
          items: brands
              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
              .toList(),
          onChanged: (val) {
            if (val == null) return;
            setState(() => _brand = val);
          },
        ),
        const Gap(12),
        DropdownButtonFormField<String>(
          initialValue: _model,
          decoration: const InputDecoration(
            labelText: 'Model',
            border: OutlineInputBorder(),
          ),
          items: models
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (val) {
            if (val == null) return;
            setState(() => _model = val);
          },
        ),
        const Gap(12),
        DropdownButtonFormField<String>(
          initialValue: _variant,
          decoration: const InputDecoration(
            labelText: 'Variant',
            border: OutlineInputBorder(),
          ),
          items: variants
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: (val) {
            if (val == null) return;
            final picked = templates.firstWhere(
              (t) => t.brand == _brand && t.model == _model && t.variant == val,
              orElse: () => templates.first,
            );
            setState(() {
              _variant = val;
              // Pull the canonical efficiency for the picked template
              _rangeEfficiency = picked.rangeEfficiency;
              if (picked.preferredChargingNetworks.isNotEmpty &&
                  _selectedNetworks.isEmpty) {
                _selectedNetworks =
                    picked.preferredChargingNetworks.toList();
              }
            });
          },
        ),
      ],
    );
  }

  /// Free-text fallback shown when the templates endpoint fails.
  Widget _buildBasicTextFields() {
    return Column(
      children: [
        TextFormField(
          initialValue: _brand,
          decoration: const InputDecoration(
            labelText: 'Brand',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _brand = v,
        ),
        const Gap(12),
        TextFormField(
          initialValue: _model,
          decoration: const InputDecoration(
            labelText: 'Model',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _model = v,
        ),
        const Gap(12),
        TextFormField(
          initialValue: _variant,
          decoration: const InputDecoration(
            labelText: 'Variant',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _variant = v,
        ),
      ],
    );
  }

  Widget _buildImagePicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reference image', style: theme.textTheme.titleSmall),
        const Gap(8),
        InkWell(
          onTap: _pickImage,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              image:
                  _imageUrl != null
                      ? DecorationImage(
                        image: _getImageProvider(_imageUrl!),
                        fit: BoxFit.cover,
                      )
                      : null,
            ),
            child:
                _imageUrl == null
                    ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIcons.camera(PhosphorIconsStyle.duotone),
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                        const Gap(8),
                        Text(
                          'Tap to add image',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    )
                    : Stack(
                      children: [
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton.filled(
                            onPressed: () => setState(() => _imageUrl = null),
                            icon: const Icon(Icons.close),
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _imageUrl = pickedFile.path);
    }
  }

  ImageProvider _getImageProvider(String path) {
    if (path.startsWith('http')) {
      return NetworkImage(path);
    } else {
      return FileImage(File(path));
    }
  }

  Widget _buildPhotoPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My vehicle photo', style: theme.textTheme.titleSmall),
        const Gap(8),
        InkWell(
          onTap: _pickPhotoFromGallery,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              image:
                  _photoFile != null
                      ? DecorationImage(
                        image: FileImage(_photoFile!),
                        fit: BoxFit.cover,
                      )
                      : _photoUrl != null
                      ? DecorationImage(
                        image: NetworkImage(_photoUrl!),
                        fit: BoxFit.cover,
                      )
                      : null,
            ),
            child:
                _photoFile == null && _photoUrl == null
                    ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIcons.camera(PhosphorIconsStyle.duotone),
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                        const Gap(8),
                        Text(
                          'Tap to upload photo',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    )
                    : _isUploading
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                      children: [
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton.filled(
                            onPressed:
                                () => setState(() {
                                  _photoFile = null;
                                  _photoUrl = null;
                                }),
                            icon: const Icon(Icons.close),
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickPhotoFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _photoFile = File(pickedFile.path);
        _isUploading = true;
      });

      // Upload to Supabase Storage
      final userId = ref.read(userProvider)?.id;
      if (userId != null) {
        final photoService = VehiclePhotoService();
        final url = await photoService.uploadPhoto(_photoFile!, userId);
        if (mounted) {
          setState(() {
            _photoUrl = url;
            _isUploading = false;
          });
        }
      } else {
        setState(() => _isUploading = false);
      }
    }
  }

  Widget _buildChargingNetworkSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preferred Charging Networks', style: theme.textTheme.titleSmall),
        const Gap(8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _availableNetworks.map((network) {
                final isSelected = _selectedNetworks.contains(network);
                return FilterChip(
                  label: Text(network),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedNetworks.add(network);
                      } else {
                        _selectedNetworks.remove(network);
                      }
                    });
                  },
                );
              }).toList(),
        ),
      ],
    );
  }

  Future<void> _saveVehicle() async {
    // Get actual user ID from user provider
    final userId = ref.read(userProvider)?.id;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to save vehicle')),
      );
      return;
    }

    final vehicle = VehicleProfile(
      id:
          widget.vehicleToEdit?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      userId: widget.vehicleToEdit?.userId ?? userId,
      brand: _brand,
      model: _model,
      variant: _variant,
      rangeEfficiency: _rangeEfficiency,
      imageUrl: _imageUrl,
      photoUrl: _photoUrl,
      preferredChargingNetworks: _selectedNetworks,
    );

    try {
      final savedVehicle =
          widget.vehicleToEdit != null
              ? await ref.read(vehicleProvider.notifier).updateVehicle(vehicle)
              : await ref.read(vehicleProvider.notifier).addVehicle(vehicle);

      if (!mounted) return;

      if (savedVehicle == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save vehicle')),
        );
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vehicle saved!')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save vehicle: $e')));
    }
  }
}
