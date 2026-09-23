import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'messages.dart';

/// UI language only. Catalog values and stored user content stay unchanged.
class AppLanguage extends ValueNotifier<Locale> {
  AppLanguage() : super(const Locale('ru'));
  static final instance = AppLanguage();
  static const supported = [Locale('ru'), Locale('en'), Locale('kk')];
  static const preferenceKey = 'event_match.ui_language';
  Future<void>? _loading;
  int _revision = 0;
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(preferenceKey);
      if (revision == _revision && supported.any((l) => l.languageCode == code)) {
        value = Locale(code!);
      }
    } catch (_) {
      // Language remains usable when local storage is unavailable.
    }
  }
  Future<void> select(String code) async {
    if (!supported.any((l) => l.languageCode == code)) return;
    _revision++;
    value = Locale(code);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(preferenceKey, code);
    } catch (_) {}
  }
}

String tr(BuildContext context, String source) =>
    translate(source, (Localizations.maybeLocaleOf(context) ?? AppLanguage.instance.value).languageCode);
String? trNullable(BuildContext context, String? source) =>
    source == null ? null : tr(context, source);
FormFieldValidator<T>? localizeValidator<T>(BuildContext context, FormFieldValidator<T>? validator) =>
    validator == null ? null : (value) => trNullable(context, validator(value));

final _templates = messages.entries.where((e) => e.key.contains(RegExp(r'\{\d+\}'))).map((e) {
  final parts = e.key.split(RegExp(r'\{\d+\}'));
  return (source: e.key, pattern: RegExp('^${parts.map(RegExp.escape).join('(.*?)')}\$', dotAll: true), values: e.value,
    weight: parts.join().length);
}).toList()..sort((a,b) => b.weight.compareTo(a.weight));

String translate(String source, String language, {bool templates = true}) {
  if (language == 'ru' || !['en','kk'].contains(language) || source.isEmpty) return source;
  final index = language == 'en' ? 0 : 1;
  final exact = messages[source];
  if (exact != null) return exact[index];
  if (templates) {
    for (final entry in _templates) {
      final match = entry.pattern.firstMatch(source);
      if (match == null) continue;
      return entry.values[index].replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
        final value = match.group(int.parse(m[1]!) + 1) ?? '';
        return translate(value, language, templates: false);
      });
    }
  }
  // Composed labels (category, city, language, dates) use canonical values.
  for (final separator in [' · ', ', ', '\n']) {
    if (source.contains(separator)) {
      return source.split(separator).map((part) => translate(part, language, templates: false)).join(separator);
    }
  }
  return source;
}

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});
  @override
  Widget build(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return PopupMenuButton<String>(
      key: const Key('language-picker'),
      tooltip: tr(context, 'Язык интерфейса'),
      initialValue: code,
      onSelected: AppLanguage.instance.select,
      itemBuilder: (_) => [
        for (final entry in const {'ru':'Русский', 'en':'English', 'kk':'Қазақша'}.entries)
          CheckedPopupMenuItem(value: entry.key, checked: code == entry.key, child: Text(entry.value)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.language, size: 20),
          const SizedBox(width: 6),
          Text(code == 'kk' ? 'ҚАЗ' : code.toUpperCase(), style: Theme.of(context).textTheme.labelLarge),
          const Icon(Icons.expand_more, size: 16),
        ]),
      ),
    );
  }
}
