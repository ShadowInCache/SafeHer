import 'models/home_summary.dart';

abstract class HomeRepository {
  Future<HomeSummary> getHomeSummary();
}
