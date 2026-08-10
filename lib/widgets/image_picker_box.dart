import 'dart:io';

import 'package:flutter/material.dart';

class ImagePickerBox extends StatelessWidget {
  final File? image;

  const ImagePickerBox({
    super.key,
    required this.image,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: image == null
          ? const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '📷',
            style: TextStyle(fontSize: 42),
          ),
          SizedBox(height: 8),
          Text(
            'Upload Base Screenshot',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'PNG • JPG • WEBP',
            style: TextStyle(
              color: Color(0xFFD1D5DB),
              fontSize: 12,
            ),
          ),
        ],
      )
          : ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          image!,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}