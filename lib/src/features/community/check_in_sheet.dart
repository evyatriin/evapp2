import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../charge/charging_service.dart';
import '../authentication/user_provider.dart';
import '../mapping/stations_repository.dart';
import '../mapping/station_model.dart';
import '../../core/backend_service.dart';

class CheckInSheet extends ConsumerStatefulWidget {
  final StationModel? station;
  
  const CheckInSheet({super.key, this.station});

  @override
  ConsumerState<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<CheckInSheet> {
  int _step = 0;
  String _selectedStatus = '';
  StationModel? _selectedStation;
  int _rating = 5;
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _batteryStartController = TextEditingController();
  final TextEditingController _batteryEndController = TextEditingController();
  final TextEditingController _timeTakenController = TextEditingController();
  final TextEditingController _costPaidController = TextEditingController();
  File? _selectedImage;
  File? _chargingSlip;
  bool _isSubmitting = false;

  // Points configuration
  static const int _basePoints = 10;
  static const int _batteryStartPoints = 2;
  static const int _batteryEndPoints = 2;
  static const int _timeTakenPoints = 1;
  static const int _costPaidPoints = 5;
  static const int _photoPoints = 5;
  static const int _slipPoints = 10;

  @override
  void initState() {
    super.initState();
    // If station is pre-provided, skip step 0
    if (widget.station != null) {
      _selectedStation = widget.station;
      _step = 1; // Go directly to status selection
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _batteryStartController.dispose();
    _batteryEndController.dispose();
    _timeTakenController.dispose();
    _costPaidController.dispose();
    super.dispose();
  }

  int _calculatePoints() {
    int points = _basePoints;
    if (_batteryStartController.text.isNotEmpty) points += _batteryStartPoints;
    if (_batteryEndController.text.isNotEmpty) points += _batteryEndPoints;
    if (_timeTakenController.text.isNotEmpty) points += _timeTakenPoints;
    if (_costPaidController.text.isNotEmpty) points += _costPaidPoints;
    if (_selectedImage != null) points += _photoPoints;
    if (_chargingSlip != null) points += _slipPoints;
    return points;
  }

  Future<void> _pickImage({bool isSlip = false}) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: isSlip ? ImageSource.gallery : ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        if (isSlip) {
          _chargingSlip = File(image.path);
        } else {
          _selectedImage = File(image.path);
        }
      });
    }
  }

  Future<String?> _uploadImage(File file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${BackendService.baseUrl}/api/chargers/upload-checkin-image'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonData = json.decode(responseData);
        return jsonData['image_url'];
      }
    } catch (e) {
      print('Error uploading image: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stationsAsync = ref.watch(stationsProvider);
    final stations = stationsAsync.asData?.value ?? [];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Check-In', style: theme.textTheme.headlineSmall),
                      if (_selectedStation != null) ...[
                        const Gap(4),
                        Text(
                          _selectedStation!.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Gap(24),
            
            // Step 0: Select Station (skip if station was pre-provided)
            if (_step == 0) ...[ 
              Text('Select a charging station', style: theme.textTheme.titleMedium),
              const Gap(16),
              if (stations.isEmpty)
                const Center(child: CircularProgressIndicator())
              else
                SizedBox(
                  height: 300,
                  child: ListView.builder(
                    itemCount: stations.length,
                    itemBuilder: (context, index) {
                      final station = stations[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            PhosphorIcons.plugCharging(PhosphorIconsStyle.duotone),
                            color: theme.colorScheme.primary,
                          ),
                          title: Text(station.name),
                          subtitle: Text(station.address ?? 'No address'),
                          trailing: _selectedStation?.id == station.id
                              ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedStation = station;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              const Gap(16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selectedStation != null
                      ? () => setState(() => _step = 1)
                      : null,
                  child: const Text('Next'),
                ),
              ),
            ]
            
            // Step 1: Select Status
            else if (_step == 1) ...[
              Text('How is this charger?', style: theme.textTheme.titleMedium),
              const Gap(16),
              Row(
                children: [
                  Expanded(child: _buildStatusBtn('Working', Colors.green, PhosphorIcons.checkCircle())),
                  const Gap(12),
                  Expanded(child: _buildStatusBtn('Busy', Colors.orange, PhosphorIcons.clock())),
                  const Gap(12),
                  Expanded(child: _buildStatusBtn('Broken', Colors.red, PhosphorIcons.xCircle())),
                ],
              ),
            ]
            
            // Step 2: Charging Details, Rating, and Images
            else if (_step == 2) ...[
              // Points Preview Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.secondaryContainer,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill), 
                         color: Colors.amber, size: 24),
                    const Gap(8),
                    Text(
                      'Points: ${_calculatePoints()}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      '/ 35 max',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(20),

              // Rating
              Text('Rate your experience', style: theme.textTheme.titleMedium),
              const Gap(8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                    onPressed: () => setState(() => _rating = index + 1),
                  );
                }),
              ),
              const Gap(16),

              // Charging Details Section
              Text('Charging Details', style: theme.textTheme.titleMedium),
              Text('Fill more for extra points!', 
                   style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
              const Gap(12),
              
              Row(
                children: [
                  Expanded(
                    child: _buildPointsTextField(
                      controller: _batteryStartController,
                      label: 'Start %',
                      hint: 'e.g. 20',
                      suffix: '%',
                      points: _batteryStartPoints,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: _buildPointsTextField(
                      controller: _batteryEndController,
                      label: 'End %',
                      hint: 'e.g. 80',
                      suffix: '%',
                      points: _batteryEndPoints,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: _buildPointsTextField(
                      controller: _timeTakenController,
                      label: 'Time',
                      hint: 'e.g. 45',
                      suffix: 'min',
                      points: _timeTakenPoints,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: _buildPointsTextField(
                      controller: _costPaidController,
                      label: 'Cost',
                      hint: 'e.g. 250',
                      prefix: '₹',
                      points: _costPaidPoints,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const Gap(16),

              // Comment
              Text('Comment (optional)', style: theme.textTheme.titleMedium),
              const Gap(8),
              TextField(
                controller: _commentController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Share your experience...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const Gap(16),

              // Photos Section
              Text('Photos', style: theme.textTheme.titleMedium),
              const Gap(8),
              Row(
                children: [
                  // Charger Photo
                  Expanded(
                    child: _buildPhotoCard(
                      file: _selectedImage,
                      label: 'Charger Photo',
                      points: _photoPoints,
                      onTap: () => _pickImage(isSlip: false),
                      onRemove: () => setState(() => _selectedImage = null),
                    ),
                  ),
                  const Gap(12),
                  // Charging Slip
                  Expanded(
                    child: _buildPhotoCard(
                      file: _chargingSlip,
                      label: 'Charging Slip',
                      points: _slipPoints,
                      onTap: () => _pickImage(isSlip: true),
                      onRemove: () => setState(() => _chargingSlip = null),
                      isSlip: true,
                    ),
                  ),
                ],
              ),
              const Gap(24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting 
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)),
                  label: Text(_isSubmitting ? 'Submitting...' : 'Submit Check-In (+${_calculatePoints()} pts)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBtn(String label, Color color, IconData icon) {
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _selectedStatus = label;
          _step = 2;
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32),
          const Gap(8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildPointsTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int points,
    String? prefix,
    String? suffix,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    final hasValue = controller.text.isNotEmpty;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: hasValue ? Colors.green.withOpacity(0.1) : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+$points',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: hasValue ? Colors.green : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const Gap(4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            suffixText: suffix,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoCard({
    required File? file,
    required String label,
    required int points,
    required VoidCallback onTap,
    required VoidCallback onRemove,
    bool isSlip = false,
  }) {
    final theme = Theme.of(context);
    final hasFile = file != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: hasFile ? Colors.green.withOpacity(0.1) : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+$points',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: hasFile ? Colors.green : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const Gap(4),
        GestureDetector(
          onTap: hasFile ? null : onTap,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              border: Border.all(
                color: hasFile ? Colors.green : theme.colorScheme.outline,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: hasFile
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.file(file, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: onRemove,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSlip 
                              ? PhosphorIcons.receipt(PhosphorIconsStyle.duotone)
                              : PhosphorIcons.camera(PhosphorIconsStyle.duotone),
                          color: theme.colorScheme.secondary,
                        ),
                        const Gap(4),
                        Text(
                          isSlip ? 'Upload' : 'Take Photo',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(userProvider);
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Upload images if selected
      String? imageUrl;
      String? slipUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage(_selectedImage!);
      }
      if (_chargingSlip != null) {
        slipUrl = await _uploadImage(_chargingSlip!);
      }

      final pointsEarned = _calculatePoints();

      await ChargingService().submitCheckIn(
        userId: user.id,
        status: _selectedStatus,
        stationId: _selectedStation?.id,
        rating: _rating,
        comment: _commentController.text.isNotEmpty ? _commentController.text : null,
        imageUrl: imageUrl,
        batteryStartPercent: int.tryParse(_batteryStartController.text),
        batteryEndPercent: int.tryParse(_batteryEndController.text),
        timeTakenMinutes: int.tryParse(_timeTakenController.text),
        costPaid: double.tryParse(_costPaidController.text),
        chargingSlipUrl: slipUrl,
        pointsEarned: pointsEarned,
        userName: user.name,
      );

      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Awesome!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill), 
                     size: 48, color: Colors.amber),
                const Gap(16),
                Text(
                  'You earned +$pointsEarned Points!',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (pointsEarned >= 30) ...[
                  const Gap(8),
                  Text(
                    '🎉 Great job providing detailed info!',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting check-in: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
