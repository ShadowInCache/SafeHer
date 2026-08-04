import 'models/search_result.dart';

abstract class SearchRepository {
  Future<SearchIndex> getSearchIndex();
}
