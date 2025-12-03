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
  const CheckInSheet({super.key});

  @override
  ConsumerState<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<CheckInSheet> {
  int _step = 0;
  String _selectedStatus = '';
  StationModel? _selectedStation;
  int _rating = 5;
  final TextEditingController _commentController = TextEditingController();
  File? _selectedImage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return null;

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${BackendService.baseUrl}/api/chargers/upload-checkin-image'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('file', _selectedImage!.path),
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
                  child: Text('Check-In', style: theme.textTheme.headlineSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Gap(24),
            
            // Step 0: Select Station
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
            
            // Step 2: Rating, Comment, and Image
            else if (_step == 2) ...[
              Text('Rate your experience', style: theme.textTheme.titleMedium),
              const Gap(16),
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
              const Gap(24),
              Text('Add a comment (optional)', style: theme.textTheme.titleMedium),
              const Gap(8),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Share your experience...',
                  border: OutlineInputBorder(),
                ),
              ),
              const Gap(24),
              Text('Add a photo (optional)', style: theme.textTheme.titleMedium),
              const Gap(8),
              if (_selectedImage != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _selectedImage!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const Gap(8),
                TextButton.icon(
                  onPressed: () => setState(() => _selectedImage = null),
                  icon: const Icon(Icons.delete),
                  label: const Text('Remove photo'),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: _pickImage,
                  icon: Icon(PhosphorIcons.camera(PhosphorIconsStyle.duotone)),
                  label: const Text('Take a photo'),
                ),
              const Gap(24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit Check-In'),
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

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      final user = ref.read(userProvider);
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Upload image if selected
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage();
      }

      await ChargingService().submitCheckIn(
        userId: user.id,
        status: _selectedStatus,
        stationId: _selectedStation?.id,
        rating: _rating,
        comment: _commentController.text.isNotEmpty ? _commentController.text : null,
        imageUrl: imageUrl,
      );

      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Awesome!'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, size: 48, color: Colors.amber),
                Gap(16),
                Text('You earned +10 Points!'),
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
