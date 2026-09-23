import '../../matching/domain/models.dart';
import 'workspace_models.dart';

abstract class WorkspaceRepository {
  Stream<Account?> watchAccount(String uid);
  Stream<StaffAccess?> watchStaff(String uid);
  Future<void> ensureAccount(
    String uid,
    String name,
    String email, {
    String accountType = 'client',
  });
  Future<void> updateName(String uid, String name);
  Future<void> deactivateAccount(String uid, {bool requestDeletion = false});
  Future<ContractorProfile?> getProfile(String uid);
  Stream<ContractorProfile?> watchProfile(String uid);
  Future<PublishedProfile?> getPublished(String uid);
  Future<List<PublishedProfile>> listPublished();
  Future<List<ContractorProfile>> listProfiles();
  Future<void> saveProfile(String uid, ProfileContent content);
  Future<void> submitProfile(String uid);
  Future<void> withdrawProfile(String uid);
  Future<void> moderateProfile(
    String actorId,
    String ownerId, {
    required bool approve,
    required String reason,
    required int expectedRevision,
  });
  Future<void> unpublish(
    String actorId,
    String ownerId, {
    required String reason,
  });
  Future<CalendarMonth?> getCalendar(String uid, DateTime month);
  Future<void> saveCalendar(String uid, CalendarMonth calendar);
  Future<List<Account>> listAccounts();
  Future<Map<String, StaffAccess>> listStaff();
  Future<void> setAccountStatus(
    String actorId,
    String targetUid, {
    required bool suspended,
    required String reason,
  });
  Future<void> setModerator(
    String actorId,
    String targetUid, {
    required bool enabled,
    required String reason,
  });
  Future<List<AuditEntry>> listAudit();
  Future<List<ClientEvent>> listEvents(String uid);
  Future<String> saveEvent(String uid, ClientEvent event);
  Future<void> deleteEvent(String uid, String eventId);
  Future<List<SavedSelection>> listSelections(String uid);
  Future<String> saveSelection(String uid, SavedSelection selection);
  Future<void> deleteSelection(String uid, String selectionId);
  Future<List<Contractor>> listFavorites(String uid);
  Future<void> setFavorite(
    String uid,
    Contractor contractor, {
    required bool favorite,
  });
}
