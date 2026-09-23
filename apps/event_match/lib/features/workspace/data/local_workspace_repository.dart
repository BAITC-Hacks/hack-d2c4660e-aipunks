import 'dart:async';
import '../../../core/local_api.dart';
import '../../matching/domain/models.dart';
import '../../planning/domain/event_plan.dart';
import '../../planning/domain/event_plan_repository.dart';
import '../domain/workspace_models.dart';
import '../domain/workspace_repository.dart';

Map<String, dynamic> _map(dynamic value) {
  final m = Map<String, dynamic>.from(value as Map);
  for (final k in ['updatedAt', 'createdAt', 'savedAt', 'confirmedAt']) {
    if (m[k] is String) m[k] = DateTime.parse(m[k] as String);
  }
  return m;
}

class LocalWorkspaceRepository extends WorkspaceRepository
    implements EventPlanRepository {
  LocalWorkspaceRepository(this.api);
  final LocalApi api;
  Future<dynamic> _call(String op, [Map<String, dynamic> data = const {}]) =>
      api.workspace(op, data);
  Stream<T?> _watch<T>(
    String op,
    String uid,
    T Function(Map<String, dynamic>) parse,
  ) {
    late final StreamController<T?> stream;
    Timer? timer;
    bool cancelled = false, busy = false;
    Future<void> poll() async {
      if (cancelled || busy) return;
      busy = true;
      try {
        final v = await _call(op, {'uid': uid});
        if (!cancelled) stream.add(v == null ? null : parse(_map(v)));
      } catch (e, stack) {
        if (!cancelled) stream.addError(e, stack);
      } finally {
        busy = false;
      }
    }

    stream = StreamController<T?>(
      onListen: () {
        poll();
        timer = Timer.periodic(const Duration(seconds: 5), (_) => poll());
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    return stream.stream;
  }

  Future<T?> _get<T>(
    String op,
    String uid,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final v = await _call(op, {'uid': uid});
    return v == null ? null : parse(_map(v));
  }

  Future<List<T>> _list<T>(
    String op,
    T Function(Map<String, dynamic>) parse, [
    String? uid,
  ]) async => [
    for (final v in await _call(op, {'uid': ?uid}) as List) parse(_map(v)),
  ];
  @override
  Stream<Account?> watchAccount(String uid) =>
      _watch('account', uid, Account.fromMap);
  @override
  Stream<StaffAccess?> watchStaff(String uid) =>
      _watch('staff', uid, StaffAccess.fromMap);
  @override
  Stream<ContractorProfile?> watchProfile(String uid) =>
      _watch('getProfile', uid, ContractorProfile.fromMap);
  @override
  Future<void> ensureAccount(String uid, String name, String email) async {
    await _call('ensureAccount', {'uid': uid});
  }

  @override
  Future<void> updateName(String uid, String name) async {
    await _call('updateName', {'uid': uid, 'name': name});
  }

  @override
  Future<void> deactivateAccount(
    String uid, {
    bool requestDeletion = false,
  }) async {
    await _call('deactivateAccount', {
      'uid': uid,
      'requestDeletion': requestDeletion,
    });
  }

  @override
  Future<ContractorProfile?> getProfile(String uid) =>
      _get('getProfile', uid, ContractorProfile.fromMap);
  @override
  Future<PublishedProfile?> getPublished(String uid) =>
      _get('getPublished', uid, PublishedProfile.fromMap);
  @override
  Future<List<PublishedProfile>> listPublished() =>
      _list('listPublished', PublishedProfile.fromMap);
  @override
  Future<List<ContractorProfile>> listProfiles() =>
      _list('listProfiles', ContractorProfile.fromMap);
  @override
  Future<void> saveProfile(String uid, ProfileContent content) async {
    await _call('saveProfile', {'uid': uid, 'content': content.toMap()});
  }

  @override
  Future<void> submitProfile(String uid) async {
    await _call('submitProfile', {'uid': uid});
  }

  @override
  Future<void> withdrawProfile(String uid) async {
    await _call('withdrawProfile', {'uid': uid});
  }

  @override
  Future<void> moderateProfile(
    String actorId,
    String ownerId, {
    required bool approve,
    required String reason,
    required int expectedRevision,
  }) async {
    await _call('moderateProfile', {
      'uid': ownerId,
      'approve': approve,
      'reason': reason,
      'expectedRevision': expectedRevision,
    });
  }

  @override
  Future<void> unpublish(
    String actorId,
    String ownerId, {
    required String reason,
  }) async {
    await _call('unpublish', {'uid': ownerId, 'reason': reason});
  }

  @override
  Future<CalendarMonth?> getCalendar(String uid, DateTime month) async {
    final v = await _call('getCalendar', {
      'uid': uid,
      'key': '${month.year}-${month.month.toString().padLeft(2, '0')}',
    });
    return v == null ? null : CalendarMonth.fromMap(_map(v));
  }

  @override
  Future<void> saveCalendar(String uid, CalendarMonth calendar) async {
    await _call('saveCalendar', {
      'uid': uid,
      'calendar': {
        'year': calendar.year,
        'month': calendar.month,
        'busyDays': calendar.busyDays,
      },
    });
  }

  @override
  Future<List<Account>> listAccounts() =>
      _list('listAccounts', Account.fromMap);
  @override
  Future<Map<String, StaffAccess>> listStaff() async =>
      (await _call('listStaff') as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, StaffAccess.fromMap(_map(v))),
      );
  @override
  Future<void> setAccountStatus(
    String actorId,
    String targetUid, {
    required bool suspended,
    required String reason,
  }) async {
    await _call('setAccountStatus', {
      'uid': targetUid,
      'suspended': suspended,
      'reason': reason,
    });
  }

  @override
  Future<void> setModerator(
    String actorId,
    String targetUid, {
    required bool enabled,
    required String reason,
  }) async {
    await _call('setModerator', {
      'uid': targetUid,
      'enabled': enabled,
      'reason': reason,
    });
  }

  @override
  Future<List<AuditEntry>> listAudit() =>
      _list('listAudit', (m) => AuditEntry.fromMap(m['id'] as String, m));
  @override
  Future<List<ClientEvent>> listEvents(String uid) => _list(
    'listEvents',
    (m) => ClientEvent.fromMap(m['id'] as String, m),
    uid,
  );
  @override
  Future<String> saveEvent(String uid, ClientEvent event) async =>
      await _call('saveEvent', {
            'uid': uid,
            'id': event.id,
            'event': event.toMap(),
          })
          as String;
  @override
  Future<void> deleteEvent(String uid, String eventId) async {
    await _call('deleteEvent', {'uid': uid, 'id': eventId});
  }

  @override
  Future<List<SavedSelection>> listSelections(String uid) => _list(
    'listSelections',
    (m) => SavedSelection.fromMap(m['id'] as String, m),
    uid,
  );
  @override
  Future<String> saveSelection(String uid, SavedSelection s) async =>
      await _call('saveSelection', {
            'uid': uid,
            'id': s.id,
            'selection': {
              'eventId': s.eventId,
              'name': s.name.length > 120 ? s.name.substring(0, 120) : s.name,
              'request': s.request.toJson(),
              'entries': [
                for (final e in s.entries)
                  {
                    'contractor': e.contractor.toJson(),
                    'explanation': e.explanation,
                  },
              ],
            },
          })
          as String;
  @override
  Future<void> deleteSelection(String uid, String selectionId) async {
    await _call('deleteSelection', {'uid': uid, 'id': selectionId});
  }

  @override
  Future<List<Contractor>> listFavorites(String uid) =>
      _list('listFavorites', Contractor.fromJson, uid);
  @override
  Future<void> setFavorite(
    String uid,
    Contractor contractor, {
    required bool favorite,
  }) async {
    await _call('setFavorite', {
      'uid': uid,
      'contractorId': contractor.id,
      'favorite': favorite,
    });
  }

  @override
  Future<EventPlan> getPlan(String uid, String eventId) async {
    final v = await _call('getPlan', {'uid': uid, 'eventId': eventId});
    return v == null
        ? EventPlan(eventId: eventId)
        : EventPlan.fromMap(eventId, _map(v));
  }

  @override
  Future<EventPlan> savePlan(String uid, EventPlan plan) async {
    try {
      return EventPlan.fromMap(
        plan.eventId,
        _map(
          await _call('savePlan', {
            'uid': uid,
            'eventId': plan.eventId,
            'plan': plan.toMap(),
          }),
        ),
      );
    } on LocalApiException catch (e) {
      if (e.status == 409) {
        throw EventPlanConflict(
          expectedRevision: plan.revision,
          actualRevision: e.details['actualRevision'] as int,
        );
      }
      rethrow;
    }
  }
}
