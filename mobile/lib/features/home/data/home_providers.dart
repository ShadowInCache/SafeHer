import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/home_repository.dart';
import '../domain/models/home_summary.dart';
import 'home_repository_mock.dart';

part 'home_providers.g.dart';

@riverpod
HomeRepository homeRepository(Ref ref) {
  return HomeRepositoryMock();
}

@riverpod
Future<HomeSummary> homeSummary(Ref ref) async {
  return ref.watch(homeRepositoryProvider).getHomeSummary();
}
