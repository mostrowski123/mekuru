import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists manual lookup corrections for manga word taps.
///
/// Overrides are scoped per book so OCR quirks in one manga do not leak into
/// unrelated titles. Each override is keyed by the resolver's original
/// surface/dictionary pair and stores the manually-entered lookup term.
class MangaLookupOverrideStorage {
  static const prefsKey = 'app.manga_lookup_overrides';

  Future<String?> loadOverride({
    required int bookId,
    required String surfaceForm,
    required String dictionaryForm,
  }) async {
    final overrides = await _loadOverrides();
    final bookOverrides = _bookOverrides(overrides, bookId);
    final value = bookOverrides[_entryKey(surfaceForm, dictionaryForm)];
    if (value is! String) return null;

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveOverride({
    required int bookId,
    required String surfaceForm,
    required String dictionaryForm,
    required String lookupTerm,
  }) async {
    final trimmedTerm = lookupTerm.trim();
    if (trimmedTerm.isEmpty) {
      await removeOverride(
        bookId: bookId,
        surfaceForm: surfaceForm,
        dictionaryForm: dictionaryForm,
      );
      return;
    }

    final overrides = await _loadOverrides();
    final bookKey = '$bookId';
    final bookOverrides = Map<String, dynamic>.from(
      _bookOverrides(overrides, bookId),
    );
    bookOverrides[_entryKey(surfaceForm, dictionaryForm)] = trimmedTerm;
    overrides[bookKey] = bookOverrides;
    await _writeOverrides(overrides);
  }

  Future<void> removeOverride({
    required int bookId,
    required String surfaceForm,
    required String dictionaryForm,
  }) async {
    final overrides = await _loadOverrides();
    final bookKey = '$bookId';
    final bookOverrides = Map<String, dynamic>.from(
      _bookOverrides(overrides, bookId),
    );
    bookOverrides.remove(_entryKey(surfaceForm, dictionaryForm));
    if (bookOverrides.isEmpty) {
      overrides.remove(bookKey);
    } else {
      overrides[bookKey] = bookOverrides;
    }
    await _writeOverrides(overrides);
  }

  Future<Map<String, dynamic>> _loadOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Ignore malformed persisted data and treat it as empty.
    }

    return {};
  }

  Future<void> _writeOverrides(Map<String, dynamic> overrides) async {
    final prefs = await SharedPreferences.getInstance();
    if (overrides.isEmpty) {
      await prefs.remove(prefsKey);
      return;
    }
    await prefs.setString(prefsKey, jsonEncode(overrides));
  }

  Map<String, dynamic> _bookOverrides(
    Map<String, dynamic> overrides,
    int bookId,
  ) {
    final value = overrides['$bookId'];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return {};
  }

  String _entryKey(String surfaceForm, String dictionaryForm) {
    return jsonEncode([surfaceForm, dictionaryForm]);
  }
}
