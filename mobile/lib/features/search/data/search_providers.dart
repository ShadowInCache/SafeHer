import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/models/search_result.dart';
import '../domain/search_repository.dart';
import 'search_repository_mock.dart';

part 'search_providers.g.dart';

@riverpod
SearchRepository searchRepository(Ref ref) {
  return SearchRepositoryMock();
}

@riverpod
Future<SearchIndex> searchIndex(Ref ref) async {
  return ref.watch(searchRepositoryProvider).getSearchIndex();
}
