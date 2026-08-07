// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reports_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$reportsRepositoryHash() => r'a462ec8fe5880cd74466b69d008a40486fba7d4d';

/// See also [reportsRepository].
@ProviderFor(reportsRepository)
final reportsRepositoryProvider =
    AutoDisposeProvider<ReportsRepository>.internal(
      reportsRepository,
      name: r'reportsRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$reportsRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ReportsRepositoryRef = AutoDisposeProviderRef<ReportsRepository>;
String _$reportsListHash() => r'd571fd61f02edcb8b5a8213d11b109cc9fcf1850';

/// See also [reportsList].
@ProviderFor(reportsList)
final reportsListProvider =
    AutoDisposeFutureProvider<List<ReportSummary>>.internal(
      reportsList,
      name: r'reportsListProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$reportsListHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ReportsListRef = AutoDisposeFutureProviderRef<List<ReportSummary>>;
String _$reportDetailHash() => r'4cff5cd177c81fd20851dca234e007ef68d1a357';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [reportDetail].
@ProviderFor(reportDetail)
const reportDetailProvider = ReportDetailFamily();

/// See also [reportDetail].
class ReportDetailFamily extends Family<AsyncValue<ReportDetail>> {
  /// See also [reportDetail].
  const ReportDetailFamily();

  /// See also [reportDetail].
  ReportDetailProvider call(String id) {
    return ReportDetailProvider(id);
  }

  @override
  ReportDetailProvider getProviderOverride(
    covariant ReportDetailProvider provider,
  ) {
    return call(provider.id);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'reportDetailProvider';
}

/// See also [reportDetail].
class ReportDetailProvider extends AutoDisposeFutureProvider<ReportDetail> {
  /// See also [reportDetail].
  ReportDetailProvider(String id)
    : this._internal(
        (ref) => reportDetail(ref as ReportDetailRef, id),
        from: reportDetailProvider,
        name: r'reportDetailProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$reportDetailHash,
        dependencies: ReportDetailFamily._dependencies,
        allTransitiveDependencies:
            ReportDetailFamily._allTransitiveDependencies,
        id: id,
      );

  ReportDetailProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.id,
  }) : super.internal();

  final String id;

  @override
  Override overrideWith(
    FutureOr<ReportDetail> Function(ReportDetailRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ReportDetailProvider._internal(
        (ref) => create(ref as ReportDetailRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        id: id,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<ReportDetail> createElement() {
    return _ReportDetailProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ReportDetailProvider && other.id == id;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, id.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ReportDetailRef on AutoDisposeFutureProviderRef<ReportDetail> {
  /// The parameter `id` of this provider.
  String get id;
}

class _ReportDetailProviderElement
    extends AutoDisposeFutureProviderElement<ReportDetail>
    with ReportDetailRef {
  _ReportDetailProviderElement(super.provider);

  @override
  String get id => (origin as ReportDetailProvider).id;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
