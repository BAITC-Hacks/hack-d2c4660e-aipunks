import '../../matching/domain/models.dart';
export '../../matching/domain/models.dart' show AvailabilityStatus;

const eventCities = ['Алматы', 'Астана', 'Зарубежье'];
const eventFormats = [
  'свадьба',
  'той',
  'корпоратив',
  'конференция',
  'юбилей',
  'день рождения',
];
const eventLanguages = ['русский', 'казахский', 'английский'];
const contractorCategories = [
  'Ведущий',
  'Фотограф',
  'Банкетный зал',
  'Флорист',
  'Декоратор',
  'Подарки и сувениры',
  'Ведущий церемонии',
  'Фото и видеобудки',
  'Отель',
  'Инструменталист',
];

class Account {
  const Account({
    required this.uid,
    required this.name,
    required this.email,
    this.status = 'active',
    this.accountType = 'client',
    this.deletionRequested = false,
    this.revision = 1,
  });
  final String uid, name, email, status, accountType;
  final bool deletionRequested;
  final int revision;
  bool get isActive => status == 'active';
  factory Account.fromMap(Map<String, dynamic> m) => Account(
    uid: m['uid'] as String,
    name: m['name'] as String,
    email: m['email'] as String,
    status: m['status'] as String,
    accountType: m['accountType'] as String? ?? 'client',
    deletionRequested: m['deletionRequested'] as bool,
    revision: m['revision'] as int,
  );
}

class StaffAccess {
  const StaffAccess({this.role = 'none', this.revision = 0});
  final String role;
  final int revision;
  bool get isAdmin => role == 'admin';
  bool get isStaff => isAdmin || role == 'moderator';
  factory StaffAccess.fromMap(Map<String, dynamic> m) =>
      StaffAccess(role: m['role'] as String, revision: m['revision'] as int);
}

class ProfileContent {
  const ProfileContent({
    this.name = '',
    this.city = 'Алматы',
    this.categories = const [],
    this.price = 0,
    this.formats = const [],
    this.languages = const [],
    this.maxHours,
    this.description = '',
    this.contact = '',
    this.portfolioUrls = const [],
  });
  final String name, city, description, contact;
  final List<String> categories, formats, languages, portfolioUrls;
  final int price;
  final double? maxHours;
  List<String> get issues => [
    if (name.trim().isEmpty) 'Укажите имя или название',
    if (!eventCities.contains(city)) 'Выберите город',
    if (categories.isEmpty) 'Выберите категорию',
    if (price <= 0 || price > 1000000000)
      'Укажите цену от 1 до 1 000 000 000 ₸',
    if (formats.isEmpty) 'Выберите форматы мероприятий',
    if (languages.isEmpty) 'Выберите языки работы',
    if (description.trim().isEmpty) 'Добавьте описание услуг',
    if (contact.trim().isEmpty) 'Добавьте деловые контакты для клиентов',
    if (maxHours != null &&
        (!maxHours!.isFinite || maxHours! <= 0 || maxHours! > 48))
      'Укажите длительность до 48 часов',
    if (portfolioUrls.length > 5 ||
        portfolioUrls.any((s) {
          final u = Uri.tryParse(s);
          return u == null || u.scheme != 'https' || u.host.isEmpty;
        }))
      'Добавьте до пяти HTTPS-ссылок на портфолио',
  ];
  Map<String, dynamic> toMap() => {
    'name': name,
    'city': city,
    'categories': categories,
    'price': price,
    'formats': formats,
    'languages': languages,
    'maxHours': maxHours,
    'description': description,
    'contact': contact,
    'portfolioUrls': portfolioUrls,
  };
  factory ProfileContent.fromMap(Map<String, dynamic> m) => ProfileContent(
    name: m['name'] as String,
    city: m['city'] as String,
    categories: List<String>.from(m['categories'] as List),
    price: m['price'] as int,
    formats: List<String>.from(m['formats'] as List),
    languages: List<String>.from(m['languages'] as List),
    maxHours: (m['maxHours'] as num?)?.toDouble(),
    description: m['description'] as String,
    contact: m['contact'] as String,
    portfolioUrls: List<String>.from(m['portfolioUrls'] as List),
  );
  Contractor toContractor(String id) => Contractor(
    id: id,
    name: name,
    city: city,
    categories: categories,
    price: price,
    formats: formats,
    languages: languages,
    busyDates: const [],
    description: description,
    maxHours: maxHours,
    isLive: true,
    contact: contact,
    portfolioUrls: portfolioUrls,
  );
}

class ContractorProfile {
  const ContractorProfile({
    required this.ownerId,
    required this.content,
    this.revision = 1,
    this.status = 'draft',
    this.reason = '',
    this.updatedAt,
  });
  final String ownerId, status, reason;
  final ProfileContent content;
  final int revision;
  final DateTime? updatedAt;
  bool get isPending => status == 'pending';
  factory ContractorProfile.fromMap(Map<String, dynamic> m) =>
      ContractorProfile(
        ownerId: m['ownerId'] as String,
        content: ProfileContent.fromMap(
          Map<String, dynamic>.from(m['content'] as Map),
        ),
        revision: m['revision'] as int,
        status: m['status'] as String,
        reason: m['reason'] as String,
        updatedAt: m['updatedAt'] as DateTime?,
      );
}

class PublishedProfile {
  const PublishedProfile({
    required this.ownerId,
    required this.content,
    required this.revision,
    required this.profileRevision,
    required this.published,
    this.updatedAt,
  });
  final String ownerId;
  final ProfileContent content;
  final int revision, profileRevision;
  final bool published;
  final DateTime? updatedAt;
  factory PublishedProfile.fromMap(Map<String, dynamic> m) => PublishedProfile(
    ownerId: m['ownerId'] as String,
    content: ProfileContent.fromMap(
      Map<String, dynamic>.from(m['content'] as Map),
    ),
    revision: m['revision'] as int,
    profileRevision: m['profileRevision'] as int,
    published: m['published'] as bool,
    updatedAt: m['updatedAt'] as DateTime?,
  );
}

class CalendarMonth {
  const CalendarMonth({
    required this.ownerId,
    required this.year,
    required this.month,
    this.busyDays = const [],
    this.confirmedAt,
  });
  final String ownerId;
  final int year, month;
  final List<int> busyDays;
  final DateTime? confirmedAt;
  String get key => '$year-${month.toString().padLeft(2, '0')}';
  int get daysInMonth => DateTime(year, month + 1, 0).day;
  bool isFresh(DateTime now) =>
      confirmedAt != null &&
      !confirmedAt!.isAfter(now) &&
      now.difference(confirmedAt!) < const Duration(days: 30);
  AvailabilityStatus availabilityOn(DateTime date, DateTime now) {
    if (date.year != year || date.month != month || !isFresh(now)) {
      return AvailabilityStatus.unconfirmed;
    }
    return busyDays.contains(date.day)
        ? AvailabilityStatus.busy
        : AvailabilityStatus.available;
  }

  factory CalendarMonth.fromMap(Map<String, dynamic> m) {
    final year = m['year'] as int, month = m['month'] as int;
    if (year < 2020 || year > 2200 || month < 1 || month > 12) {
      throw const FormatException('Invalid calendar month');
    }
    final days = List<int>.from(m['busyDays'] as List);
    if (days.any((d) => d < 1 || d > DateTime(year, month + 1, 0).day)) {
      throw const FormatException('Invalid day');
    }
    return CalendarMonth(
      ownerId: m['ownerId'] as String,
      year: year,
      month: month,
      busyDays: days,
      confirmedAt: m['confirmedAt'] as DateTime?,
    );
  }
}

class ClientEvent {
  const ClientEvent({
    this.id = '',
    required this.name,
    required this.city,
    required this.date,
    required this.format,
    this.preferences = '',
  });
  final String id, name, city, format, preferences;
  final DateTime date;
  Map<String, dynamic> toMap() => {
    'name': name,
    'city': city,
    'date': dateKey(date),
    'format': format,
    'preferences': preferences,
  };
  factory ClientEvent.fromMap(String id, Map<String, dynamic> m) => ClientEvent(
    id: id,
    name: m['name'] as String,
    city: m['city'] as String,
    date: DateTime.parse(m['date'] as String),
    format: m['format'] as String,
    preferences: m['preferences'] as String,
  );
}

Map<String, dynamic> contractorSnapshot(Contractor c) => {
  'id': c.id,
  'anon_name': c.name,
  'city': c.city,
  'categories': c.categories,
  'price_from_kzt': c.price,
  'event_formats': c.formats,
  'languages': c.languages,
  'max_hours': c.maxHours,
  'busy_dates': c.busyDates,
  'description': c.description,
  'synthetic': c.synthetic,
  'city_imputed': c.cityImputed,
  'price_imputed': c.priceImputed,
  'is_live': c.isLive,
  'contact': c.contact,
  'portfolio_urls': c.portfolioUrls,
};

class SavedSelection {
  const SavedSelection({
    this.id = '',
    required this.eventId,
    required this.name,
    required this.request,
    required this.entries,
    this.savedAt,
  });
  final String id, eventId, name;
  final MatchRequest request;
  final List<Recommendation> entries;
  final DateTime? savedAt;
  factory SavedSelection.fromMap(String id, Map<String, dynamic> m) =>
      SavedSelection(
        id: id,
        eventId: m['eventId'] as String,
        name: m['name'] as String,
        request: MatchRequest.fromJson(
          Map<String, dynamic>.from(m['request'] as Map),
        ),
        entries: (m['entries'] as List)
            .map(
              (e) => Recommendation(
                Contractor.fromJson(
                  Map<String, dynamic>.from(e['contractor'] as Map),
                ),
                e['explanation'] as String,
              ),
            )
            .toList(),
        savedAt: m['savedAt'] as DateTime?,
      );
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.actorId,
    required this.action,
    required this.resourceType,
    required this.resourceId,
    required this.revision,
    required this.reason,
    this.createdAt,
  });
  final String id, actorId, action, resourceType, resourceId, reason;
  final int revision;
  final DateTime? createdAt;
  factory AuditEntry.fromMap(String id, Map<String, dynamic> m) => AuditEntry(
    id: id,
    actorId: m['actorId'] as String,
    action: m['action'] as String,
    resourceType: m['resourceType'] as String,
    resourceId: m['resourceId'] as String,
    revision: m['revision'] as int,
    reason: m['reason'] as String,
    createdAt: m['createdAt'] as DateTime?,
  );
}
