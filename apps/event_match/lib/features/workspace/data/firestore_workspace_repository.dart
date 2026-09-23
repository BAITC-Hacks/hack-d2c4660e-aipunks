import 'package:cloud_firestore/cloud_firestore.dart';
import '../../matching/domain/models.dart';
import '../domain/workspace_models.dart';
import '../domain/workspace_repository.dart';

/// Client writes remain subject to firestore.rules, including every transaction.
class FirestoreWorkspaceRepository extends WorkspaceRepository {
  FirestoreWorkspaceRepository(this.db);
  final FirebaseFirestore db;
  DocumentReference<Map<String, dynamic>> _doc(String path) => db.doc(path);
  Map<String, dynamic> _map(DocumentSnapshot<Map<String, dynamic>> doc) =>
      _normalize(doc.data()!) as Map<String, dynamic>;
  dynamic _normalize(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _normalize(v)));
    }
    if (value is List) return value.map(_normalize).toList();
    return value;
  }

  Stream<T?> _watch<T>(String path, T Function(Map<String, dynamic>) parse) =>
      _doc(path).snapshots().map((d) => d.exists ? parse(_map(d)) : null);
  Future<T?> _get<T>(
    String path,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final doc = await _doc(path).get(const GetOptions(source: Source.server));
    return doc.exists ? parse(_map(doc)) : null;
  }

  @override
  Stream<Account?> watchAccount(String uid) =>
      _watch('accounts/$uid', Account.fromMap);
  @override
  Stream<StaffAccess?> watchStaff(String uid) =>
      _watch('staffAccess/$uid', StaffAccess.fromMap);
  @override
  Future<void> ensureAccount(String uid, String name, String email) =>
      db.runTransaction((tx) async {
        final ref = _doc('accounts/$uid');
        if ((await tx.get(ref)).exists) return;
        tx.set(ref, {
          'uid': uid,
          'name': name.trim(),
          'email': email,
          'status': 'active',
          'deletionRequested': false,
          'revision': 1,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
  @override
  Future<void> updateName(String uid, String name) =>
      db.runTransaction((tx) async {
        if (name.trim().isEmpty || name.length > 120) {
          throw ArgumentError('Укажите имя до 120 символов');
        }
        final ref = _doc('accounts/$uid');
        final d = (await tx.get(ref)).data()!;
        tx.update(ref, {
          'name': name.trim(),
          'revision': (d['revision'] as int) + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
  void _audit(
    Transaction tx,
    String actor,
    String type,
    String id,
    int revision,
    String action,
    String reason,
  ) {
    tx.set(_doc('audit/${type}_${id}_$revision'), {
      'actorId': actor,
      'action': action,
      'resourceType': type,
      'resourceId': id,
      'revision': revision,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _hide(
    Transaction tx,
    String actor,
    String uid,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String reason,
  ) {
    final data = snapshot.data();
    if (data == null || data['published'] != true) return;
    final rev = (data['revision'] as int) + 1;
    tx.update(snapshot.reference, {
      'published': false,
      'revision': rev,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _audit(tx, actor, 'publication', uid, rev, 'unpublished', reason);
  }

  Future<void> _status(
    String actor,
    String uid,
    String status,
    String reason, {
    bool requestDeletion = false,
  }) => db.runTransaction((tx) async {
    final accountRef = _doc('accounts/$uid');
    final account = (await tx.get(accountRef)).data();
    final pub = await tx.get(_doc('publishedProfiles/$uid'));
    if (account == null) throw StateError('Аккаунт не найден');
    if (account['status'] == status) {
      throw StateError('Статус уже изменён. Обновите страницу.');
    }
    final rev = (account['revision'] as int) + 1;
    tx.update(accountRef, {
      'status': status,
      'deletionRequested':
          requestDeletion || account['deletionRequested'] == true,
      'revision': rev,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _audit(tx, actor, 'account', uid, rev, status, reason);
    if (status != 'active') _hide(tx, actor, uid, pub, reason);
  });
  @override
  Future<void> deactivateAccount(String uid, {bool requestDeletion = false}) =>
      _status(
        uid,
        uid,
        'deactivated',
        requestDeletion
            ? 'Запрос владельца на удаление данных'
            : 'Деактивация владельцем',
        requestDeletion: requestDeletion,
      );
  @override
  Future<void> setAccountStatus(
    String actorId,
    String targetUid, {
    required bool suspended,
    required String reason,
  }) => _status(actorId, targetUid, suspended ? 'suspended' : 'active', reason);
  @override
  Future<ContractorProfile?> getProfile(String uid) =>
      _get('profiles/$uid', ContractorProfile.fromMap);
  @override
  Stream<ContractorProfile?> watchProfile(String uid) =>
      _watch('profiles/$uid', ContractorProfile.fromMap);
  @override
  Future<PublishedProfile?> getPublished(String uid) =>
      _get('publishedProfiles/$uid', PublishedProfile.fromMap);
  @override
  Future<List<PublishedProfile>> listPublished() async {
    final rows = await db
        .collection('publishedProfiles')
        .where('published', isEqualTo: true)
        .get(const GetOptions(source: Source.server));
    final profiles = <PublishedProfile>[];
    for (final row in rows.docs) {
      try {
        profiles.add(PublishedProfile.fromMap(_map(row)));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return profiles..sort((a, b) => a.ownerId.compareTo(b.ownerId));
  }

  @override
  Future<List<ContractorProfile>> listProfiles() async =>
      (await db
              .collection('profiles')
              .get(const GetOptions(source: Source.server)))
          .docs
          .map((d) => ContractorProfile.fromMap(_map(d)))
          .toList();
  @override
  Future<void> saveProfile(String uid, ProfileContent content) =>
      db.runTransaction((tx) async {
        final ref = _doc('profiles/$uid');
        final old = (await tx.get(ref)).data();
        if (old?['status'] == 'pending') {
          throw StateError('Сначала отзовите профиль с проверки');
        }
        tx.set(ref, {
          'ownerId': uid,
          'revision': ((old?['revision'] as int?) ?? 0) + 1,
          'status': 'draft',
          'content': content.toMap(),
          'reason': '',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
  Future<void> _profileStatus(String uid, String status) =>
      db.runTransaction((tx) async {
        final ref = _doc('profiles/$uid');
        final old = (await tx.get(ref)).data();
        if (old == null) throw StateError('Сначала сохраните профиль');
        if (status == 'pending') {
          if (old['status'] == 'pending') {
            throw StateError('Профиль уже на проверке');
          }
          final issues = ProfileContent.fromMap(
            Map<String, dynamic>.from(old['content'] as Map),
          ).issues;
          if (issues.isNotEmpty) throw StateError(issues.join('. '));
        } else if (old['status'] != 'pending') {
          throw StateError('Профиль больше не на проверке');
        }
        tx.update(ref, {
          'status': status,
          'revision': (old['revision'] as int) + 1,
          'reason': '',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
  @override
  Future<void> submitProfile(String uid) => _profileStatus(uid, 'pending');
  @override
  Future<void> withdrawProfile(String uid) => _profileStatus(uid, 'draft');
  @override
  Future<void> moderateProfile(
    String actorId,
    String ownerId, {
    required bool approve,
    required String reason,
    required int expectedRevision,
  }) => db.runTransaction((tx) async {
    final ref = _doc('profiles/$ownerId');
    final old = (await tx.get(ref)).data();
    final pubRef = _doc('publishedProfiles/$ownerId');
    final pub = (await tx.get(pubRef)).data();
    if (old == null ||
        old['status'] != 'pending' ||
        old['revision'] != expectedRevision) {
      throw StateError('Версия изменилась. Обновите очередь проверки.');
    }
    final rev = expectedRevision + 1;
    final status = approve ? 'approved' : 'changes_requested';
    tx.update(ref, {
      'status': status,
      'revision': rev,
      'reason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _audit(tx, actorId, 'profile', ownerId, rev, status, reason);
    if (approve) {
      tx.set(pubRef, {
        'ownerId': ownerId,
        'revision': ((pub?['revision'] as int?) ?? 0) + 1,
        'profileRevision': rev,
        'published': true,
        'content': old['content'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  });
  @override
  Future<void> unpublish(
    String actorId,
    String ownerId, {
    required String reason,
  }) => db.runTransaction((tx) async {
    final pub = await tx.get(_doc('publishedProfiles/$ownerId'));
    if (!pub.exists || pub.data()?['published'] != true) {
      throw StateError('Карточка уже снята с публикации');
    }
    _hide(tx, actorId, ownerId, pub, reason);
  });
  @override
  Future<CalendarMonth?> getCalendar(String uid, DateTime month) async {
    final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    try {
      return await _get('calendars/$uid/months/$key', CalendarMonth.fromMap);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> saveCalendar(String uid, CalendarMonth calendar) async {
    if (calendar.ownerId != uid ||
        calendar.month < 1 ||
        calendar.month > 12 ||
        calendar.busyDays.any((d) => d < 1 || d > calendar.daysInMonth)) {
      throw ArgumentError('Проверьте календарь');
    }
    await _doc('calendars/$uid/months/${calendar.key}').set({
      'ownerId': uid,
      'year': calendar.year,
      'month': calendar.month,
      'busyDays': calendar.busyDays.toSet().toList()..sort(),
      'confirmedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<List<Account>> listAccounts() async =>
      (await db
              .collection('accounts')
              .get(const GetOptions(source: Source.server)))
          .docs
          .map((d) => Account.fromMap(_map(d)))
          .toList();
  @override
  Future<Map<String, StaffAccess>> listStaff() async => {
    for (final d
        in (await db
                .collection('staffAccess')
                .get(const GetOptions(source: Source.server)))
            .docs)
      d.id: StaffAccess.fromMap(_map(d)),
  };
  @override
  Future<void> setModerator(
    String actorId,
    String targetUid, {
    required bool enabled,
    required String reason,
  }) => db.runTransaction((tx) async {
    final ref = _doc('staffAccess/$targetUid');
    final old = (await tx.get(ref)).data();
    if (old?['role'] == 'admin') {
      throw StateError('Администраторы назначаются служебным инструментом');
    }
    final rev = ((old?['revision'] as int?) ?? 0) + 1;
    final role = enabled ? 'moderator' : 'none';
    tx.set(ref, {
      'role': role,
      'revision': rev,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _audit(tx, actorId, 'staff', targetUid, rev, role, reason);
  });
  @override
  Future<List<AuditEntry>> listAudit() async =>
      (await db
              .collection('audit')
              .orderBy('createdAt', descending: true)
              .limit(100)
              .get(const GetOptions(source: Source.server)))
          .docs
          .map((d) => AuditEntry.fromMap(d.id, _map(d)))
          .toList();
  @override
  Future<List<ClientEvent>> listEvents(String uid) async =>
      (await db
              .collection('accounts/$uid/events')
              .orderBy('updatedAt', descending: true)
              .get(const GetOptions(source: Source.server)))
          .docs
          .map((d) => ClientEvent.fromMap(d.id, _map(d)))
          .toList();
  @override
  Future<String> saveEvent(String uid, ClientEvent event) async {
    if (event.name.trim().isEmpty ||
        event.name.length > 120 ||
        !eventCities.contains(event.city) ||
        !eventFormats.contains(event.format) ||
        !MatchDatePolicy.live().contains(event.date)) {
      throw ArgumentError('Проверьте название и дату мероприятия');
    }
    final ref = event.id.isEmpty
        ? db.collection('accounts/$uid/events').doc()
        : _doc('accounts/$uid/events/${event.id}');
    await ref.set({
      ...event.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> deleteEvent(String uid, String eventId) async {
    final selections = await db
        .collection('accounts/$uid/selections')
        .where('eventId', isEqualTo: eventId)
        .get(const GetOptions(source: Source.server));
    if (selections.docs.isNotEmpty) {
      throw StateError('Сначала удалите подборки этого мероприятия');
    }
    await _doc('accounts/$uid/events/$eventId').delete();
  }

  @override
  Future<List<SavedSelection>> listSelections(String uid) async {
    final docs = await db
        .collection('accounts/$uid/selections')
        .orderBy('savedAt', descending: true)
        .get(const GetOptions(source: Source.server));
    final result = <SavedSelection>[];
    for (final d in docs.docs) {
      try {
        result.add(SavedSelection.fromMap(d.id, _map(d)));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return result;
  }

  @override
  Future<String> saveSelection(String uid, SavedSelection selection) async {
    selection.request.validate(datePolicy: MatchDatePolicy.live());
    if (selection.entries.length > 3 ||
        selection.entries.any((e) => !e.contractor.isLive)) {
      throw ArgumentError(
        'Сохранять можно только живые подборки до трёх карточек',
      );
    }
    final ref = selection.id.isEmpty
        ? db.collection('accounts/$uid/selections').doc()
        : _doc('accounts/$uid/selections/${selection.id}');
    await ref.set({
      'eventId': selection.eventId,
      // Event names and category names each fit their own limits; the combined
      // display label is bounded independently from the stored event title.
      'name': selection.name.length <= 120
          ? selection.name
          : '${String.fromCharCodes(selection.name.runes.take(100))}…',
      'request': selection.request.toJson(),
      'entries': selection.entries
          .map(
            (e) => {
              'contractor': contractorSnapshot(e.contractor),
              'explanation': e.explanation,
            },
          )
          .toList(),
      'savedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> deleteSelection(String uid, String selectionId) =>
      _doc('accounts/$uid/selections/$selectionId').delete();
  @override
  Future<List<Contractor>> listFavorites(String uid) async {
    final docs = await db
        .collection('accounts/$uid/favorites')
        .orderBy('savedAt', descending: true)
        .get(const GetOptions(source: Source.server));
    final result = <Contractor>[];
    for (final d in docs.docs) {
      try {
        result.add(
          Contractor.fromJson(
            Map<String, dynamic>.from(d.data()['contractor'] as Map),
          ),
        );
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return result;
  }

  @override
  Future<void> setFavorite(
    String uid,
    Contractor contractor, {
    required bool favorite,
  }) async {
    final ref = _doc('accounts/$uid/favorites/${contractor.id}');
    if (!favorite) {
      await ref.delete();
      return;
    }
    if (!contractor.isLive) {
      throw ArgumentError(
        'Демонстрационные профили нельзя добавлять в живое избранное',
      );
    }
    await ref.set({
      'contractor': contractorSnapshot(contractor),
      'savedAt': FieldValue.serverTimestamp(),
    });
  }
}
