import 'dart:typed_data';
import 'package:flutter/material.dart';

class MockPhoto {
  final String id;
  final String title;
  final Color tintColor;
  final IconData icon;
  final Uint8List? imageBytes;
  final bool isVerified;
  final double aiConfidence;
  final String? aiReason;
  final String? description;

  const MockPhoto({
    required this.id,
    required this.title,
    required this.tintColor,
    required this.icon,
    this.imageBytes,
    this.isVerified = false,
    this.aiConfidence = 0.0,
    this.aiReason,
    this.description,
  });
}
