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

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Vehicle' : 'Add Vehicle'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Gap(20),
          Icon(
            PhosphorIcons.carProfile(PhosphorIconsStyle.duotone),
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const Gap(32),
          _buildDropdown(
            context,
            label: 'Brand',
            value: _brand,
            items: ['Tata', 'MG', 'Hyundai', 'Mahindra'],
            onChanged: (val) => setState(() => _brand = val!),
          ),
          const Gap(16),
          _buildDropdown(
            context,
            label: 'Model',
            value: _model,
            items: ['Nexon EV', 'Tiago EV', 'ZS EV', 'Kona', 'XUV 400'],
            onChanged: (val) => setState(() => _model = val!),
          ),
          const Gap(16),
          _buildDropdown(
            context,
            label: 'Variant',
            value: _variant,
            items: ['Prime', 'Max', 'Excite', 'Exclusive'],
            onChanged: (val) => setState(() => _variant = val!),
          ),
          const Gap(16),
          _buildImagePicker(theme),
          const Gap(16),
          _buildPhotoPicker(theme),
          const Gap(16),
          _buildChargingNetworkSelector(theme),
          const Gap(40),
          Text(
            'Real World Range Estimate',
            style: theme.textTheme.titleMedium,
          ),
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
                      '${(400.0 * _rangeEfficiency).toInt()} km', // Mock base range
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.tertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(40),
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

  Widget _buildDropdown(
    BuildContext context, {
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : items.first,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildImagePicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vehicle Image', style: theme.textTheme.titleSmall),
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
              image: _imageUrl != null
                  ? DecorationImage(
                      image: _getImageProvider(_imageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _imageUrl == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIcons.camera(PhosphorIconsStyle.duotone), size: 32, color: theme.colorScheme.primary),
                      const Gap(8),
                      Text('Tap to add image', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
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
                          style: IconButton.styleFrom(backgroundColor: theme.colorScheme.error),
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
        Text('Vehicle Photo (from Storage)', style: theme.textTheme.titleSmall),
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
              image: _photoFile != null
                  ? DecorationImage(image: FileImage(_photoFile!), fit: BoxFit.cover)
                  : _photoUrl != null
                      ? DecorationImage(image: NetworkImage(_photoUrl!), fit: BoxFit.cover)
                      : null,
            ),
            child: _photoFile == null && _photoUrl == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIcons.camera(PhosphorIconsStyle.duotone), size: 32, color: theme.colorScheme.primary),
                      const Gap(8),
                      Text('Tap to upload photo', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
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
                              onPressed: () => setState(() {
                                _photoFile = null;
                                _photoUrl = null;
                              }),
                              icon: const Icon(Icons.close),
                              style: IconButton.styleFrom(backgroundColor: theme.colorScheme.error),
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
          children: _availableNetworks.map((network) {
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

  void _saveVehicle() {
    // Get actual user ID from user provider
    final userId = ref.read(userProvider)?.id;
    
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to save vehicle')),
      );
      return;
    }
    
    final vehicle = VehicleProfile(
      id: widget.vehicleToEdit?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      userId: widget.vehicleToEdit?.userId ?? userId,
      brand: _brand,
      model: _model,
      variant: _variant,
      rangeEfficiency: _rangeEfficiency,
      imageUrl: _imageUrl,
      photoUrl: _photoUrl,
      preferredChargingNetworks: _selectedNetworks,
    );

    if (widget.vehicleToEdit != null) {
      ref.read(vehicleProvider.notifier).updateVehicle(vehicle);
    } else {
      ref.read(vehicleProvider.notifier).addVehicle(vehicle);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vehicle Saved!')),
    );
    context.pop();
  }
}
