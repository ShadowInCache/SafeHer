import 'package:safeher_app/core/local/local_key_value_store.dart';

/// In-memory [LocalKeyValueStore] for widget tests — avoids needing
/// `Hive.initFlutter()`, which widget tests never call.
class FakeKeyValueStore implements LocalKeyValueStore {
  final _bools = <String, bool>{};
  final _doubles = <String, double>{};
  final _ints = <String, int>{};

  @override
  bool getBool(String key, {bool defaultValue = false}) => _bools[key] ?? defaultValue;

  @override
  Future<void> setBool(String key, bool value) async => _bools[key] = value;

  @override
  double getDouble(String key, {double defaultValue = 0}) => _doubles[key] ?? defaultValue;

  @override
  Future<void> setDouble(String key, double value) async => _doubles[key] = value;

  @override
  int getInt(String key, {int defaultValue = 0}) => _ints[key] ?? defaultValue;

  @override
  Future<void> setInt(String key, int value) async => _ints[key] = value;
}
