import 'package:flutter/material.dart';

/// Shared visual language for future features. Pastels are surfaces, not text.
abstract final class AppColors {
  static const canvas = Color(0xFFFAF9F6);
  static const ink = Color(0xFF292632);
  static const muted = Color(0xFF696572);
  static const primary = Color(0xFF625080);
  static const lavender = Color(0xFFEDE8F2);
  static const peach = Color(0xFFF7E6DB);
  static const sage = Color(0xFFE5EDE2);
  static const blue = Color(0xFFE4EBF4);
  static const border = Color(0xFFE5DFE8);
  static const white = Color(0xFFFFFFFF);
  static const hero = Color(0xFFE4DCEE);
  static const plum = Color(0xFF40334F);

  static Color categorySurface(String category) => switch (category) {
    'Флорист' || 'Декоратор' => sage,
    'Ведущий' || 'Ведущий церемонии' => lavender,
    'Фотограф' || 'Фото и видеобудки' => peach,
    _ => blue,
  };
}
