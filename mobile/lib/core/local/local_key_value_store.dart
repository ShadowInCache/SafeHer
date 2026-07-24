import 'package:hive_flutter/hive_flutter.dart';

/// Minimal key-value persistence abstraction so callers (and their tests)
/// aren't coupled to Hive directly — matches the "repository abstraction
/// for every data source" rule.
abstract class LocalKeyValueStore {
  bool getBool(String key, {bool defaultValue = false});
  Future<void> setBool(String key, bool value);
}

class HiveKeyValueStore implements LocalKeyValueStore {
  const HiveKeyValueStore(this._box);

  final Box _box;

  @override
  bool getBool(String key, {bool defaultValue = false}) => _box.get(key, defaultValue: defaultValue) as bool;

  @override
  Future<void> setBool(String key, bool value) => _box.put(key, value);
}
