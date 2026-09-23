import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'models.dart';

Object? canonicalObject(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: canonicalObject(value[k])};
  }
  if (value is List) return value.map(canonicalObject).toList();
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return value;
}

String catalogVersion(List<Contractor> catalog) {
  final sorted = [...catalog]..sort((a, b) => a.id.compareTo(b.id));
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(canonicalObject(sorted.map((c) => c.toJson()).toList())),
        ),
      )
      .toString();
}
