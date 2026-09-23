import 'package:flutter/material.dart';

/// Shared visual language for future features. Pastels are surfaces, not text.
abstract final class AppColors {
  static const canvas = Color(0xFFFAF8F5);
  static const ink = Color(0xFF302D3B);
  static const muted = Color(0xFF696472);
  static const primary = Color(0xFF69568B);
  static const lavender = Color(0xFFEDE6F5);
  static const peach = Color(0xFFF7E6DB);
  static const sage = Color(0xFFE5EDE2);
  static const blue = Color(0xFFE4EBF4);
  static const border = Color(0xFFE5DFE8);
  static const white = Color(0xFFFFFFFF);

  static Color categorySurface(String category) => switch (category) {
    'Флорист' || 'Декоратор' => sage,
    'Ведущий' || 'Ведущий церемонии' => lavender,
    'Фотограф' || 'Фото и видеобудки' => peach,
    _ => blue,
  };
}
