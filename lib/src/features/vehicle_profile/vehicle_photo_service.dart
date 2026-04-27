import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VehiclePhotoService {
  final _supabase = Supabase.instance.client;

  /// Upload vehicle photo to Supabase Storage
  Future<String?> uploadPhoto(File photo, String userId) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$userId/$timestamp.jpg';

      final response = await _supabase.storage
          .from('vehicle-photos')
          .upload(fileName, photo);

      if (response.isNotEmpty) {
        return getPhotoUrl(fileName);
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      return null;
    }
  }

  /// Get public URL for a photo
  String getPhotoUrl(String path) {
    return _supabase.storage.from('vehicle-photos').getPublicUrl(path);
  }

  /// Delete photo from Supabase Storage
  Future<bool> deletePhoto(String photoUrl) async {
    try {
      // Extract path from URL
      final uri = Uri.parse(photoUrl);
      final marker = '/storage/v1/object/public/vehicle-photos/';
      final fullPath = uri.path;
      if (!fullPath.contains(marker)) {
        return false;
      }
      final path = fullPath.split(marker).last;
      if (path.isEmpty) {
        return false;
      }

      await _supabase.storage.from('vehicle-photos').remove([path]);

      return true;
    } catch (e) {
      debugPrint('Error deleting photo: $e');
      return false;
    }
  }
}
