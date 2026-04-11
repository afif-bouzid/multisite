import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
class ImageInputCard extends StatelessWidget {
  final XFile? imageFile;
  final String? imageUrl;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final String label;
  final double size; 
  const ImageInputCard({
    super.key,
    required this.imageFile,
    required this.imageUrl,
    required this.onPick,
    required this.onRemove,
    this.label = "Photo",
    this.size = 140, 
  });
  @override
  Widget build(BuildContext context) {
    final bool hasImage = imageFile != null || (imageUrl != null && imageUrl!.isNotEmpty);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[400]!),
              image: hasImage ? _buildDecorationImage() : null,
            ),
            child: !hasImage
                ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo, size: size * 0.3, color: Colors.grey[600]),
                if (size > 80) ...[
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ]
              ],
            )
                : null,
          ),
        ),
        if (hasImage)
          Positioned(
            top: -6,
            right: -6,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
      ],
    );
  }
  DecorationImage _buildDecorationImage() {
    if (imageFile != null) {
      if (kIsWeb) {
        return DecorationImage(image: NetworkImage(imageFile!.path), fit: BoxFit.cover);
      }
      return DecorationImage(image: FileImage(File(imageFile!.path)), fit: BoxFit.cover);
    } else {
      return DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover);
    }
  }
}
