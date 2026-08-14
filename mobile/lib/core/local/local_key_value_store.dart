import 'package:hive_flutter/hive_flutter.dart';

/// Minimal key-value persistence abstraction so callers (and their tests)
/// aren't coupled to Hive directly — matches the "repository abstraction
/// for every data source" rule.
abstract class LocalKeyValueStore {
  bool getBool(String key, {bool defaultValue = false});
  Future<void> setBool(String key, bool value);
  double getDouble(String key, {double defaultValue = 0});
  Future<void> setDouble(String key, double value);
  int getInt(String key, {int defaultValue = 0});
  Future<void> setInt(String key, int value);
}

class HiveKeyValueStore implements LocalKeyValueStore {
  const HiveKeyValueStore(this._box);

  final Box _box;

  @override
  bool getBool(String key, {bool defaultValue = false}) => _box.get(key, defaultValue: defaultValue) as bool;

  @override
  Future<void> setBool(String key, bool value) => _box.put(key, value);

  @override
  double getDouble(String key, {double defaultValue = 0}) => (_box.get(key, defaultValue: defaultValue) as num).toDouble();

  @override
  Future<void> setDouble(String key, double value) => _box.put(key, value);

  @override
  int getInt(String key, {int defaultValue = 0}) => _box.get(key, defaultValue: defaultValue) as int;

  @override
  Future<void> setInt(String key, int value) => _box.put(key, value);
}
