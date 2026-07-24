/// Abstract session/auth interface. See data/ for the mock (dev flavor) and
/// eventual Firebase-backed (prod flavor) implementations.
abstract class AuthRepository {
  Future<bool> hasActiveSession();
}
