import '../../matching/domain/models.dart';
import '../../workspace/domain/workspace_models.dart';
import 'event_plan.dart';

class PlanCandidate {
  const PlanCandidate({
    required this.recommendation,
    required this.currentContractor,
    required this.selectionId,
    required this.category,
    required this.isSelected,
    required this.warnings,
    required this.blockers,
    required this.draftBrief,
  });

  /// The original recommendation is a historical snapshot.
  final Recommendation recommendation;
  final Contractor? currentContractor;
  final String selectionId, category;
  final bool isSelected;
  final List<String> warnings, blockers;
  final String draftBrief;
  Contractor get contractor => currentContractor ?? recommendation.contractor;
  String get contractorId => recommendation.contractor.id;
  String get name => contractor.name;
  int? get currentPriceKzt => currentContractor?.price;
  bool get canChoose => blockers.isEmpty;
}

class PlanSelectionReview {
  const PlanSelectionReview({
    required this.selection,
    required this.candidates,
    required this.staleBrief,
  });
  final SavedSelection selection;
  final List<PlanCandidate> candidates;
  final bool staleBrief;
  String get category => selection.request.category;
  String get name => selection.name;
}

class EventPlanReview {
  const EventPlanReview({
    required this.groups,
    required this.selectedCandidates,
    required this.unresolvedCategories,
    required this.categoryCount,
    required this.estimatedFromKzt,
    required this.remainingBudgetKzt,
    required this.exceedsBudget,
  });

  final List<PlanSelectionReview> groups;
  final List<PlanCandidate> selectedCandidates;
  final List<String> unresolvedCategories;
  final int categoryCount;

  /// Null means no current valid price is selected; zero would be misleading.
  final int? estimatedFromKzt;

  /// Only provided when every represented category has a valid choice.
  final int? remainingBudgetKzt;
  final bool exceedsBudget;
  int get selectedCount => selectedCandidates.length;
  int get unresolvedCount => unresolvedCategories.length;
}

/// Rechecks historical selections against current publications and calendars.
/// All inputs, including time, are explicit to keep the review deterministic.
class EventPlanEngine {
  const EventPlanEngine();

  EventPlanReview build({
    required ClientEvent event,
    required List<SavedSelection> selections,
    required EventPlan plan,
    required Map<String, PublishedProfile> published,
    required Map<String, CalendarMonth?> calendars,
    required DateTime now,
  }) {
    plan.validate();
    if (plan.eventId != event.id) {
      throw ArgumentError('План относится к другому мероприятию');
    }
    final groups = <PlanSelectionReview>[];
    final categories = <String>{};
    final selected = <String, PlanCandidate>{};
    for (final selection in selections) {
      if (selection.eventId != event.id) continue;
      final request = selection.request;
      categories.add(request.category);
      final stale =
          event.city != request.city ||
          dateKey(event.date) != dateKey(request.date) ||
          event.format != request.format ||
          event.preferences.trim() != request.preferences.trim();
      var validRequest = true;
      try {
        request.validate(datePolicy: MatchDatePolicy.live(now));
        if (request.budget > 1000000000 ||
            (request.hours != null && request.hours! > 48)) {
          validRequest = false;
        }
      } on ArgumentError {
        validRequest = false;
      }
      final candidates = <PlanCandidate>[];
      for (final recommendation in selection.entries.take(3)) {
        final snapshot = recommendation.contractor;
        final publication = published[snapshot.id];
        final current =
            publication != null &&
                publication.published &&
                publication.ownerId == snapshot.id
            ? publication.content.toContractor(snapshot.id)
            : null;
        final warnings = <String>[];
        final blockers = <String>[];
        if (!validRequest) {
          blockers.add('Условия сохранённой подборки требуют обновления.');
        }
        if (stale) {
          blockers.add('Условия мероприятия изменились. Обновите подборку.');
        }
        if (!MatchDatePolicy.live(now).contains(event.date)) {
          blockers.add('Для выбора нужна дата в ближайшие 365 дней.');
        }
        if (!contractorCategories.contains(request.category)) {
          blockers.add('Категория подборки больше не поддерживается.');
        }
        if (!snapshot.isLive) {
          blockers.add(
            'Демонстрационную карточку нельзя выбрать в живой план.',
          );
        }
        if (current == null) {
          blockers.add('Карточка больше не опубликована.');
        } else {
          if (current.price != snapshot.price) {
            warnings.add(
              'Цена изменилась: было от ${snapshot.price} ₸, '
              'теперь от ${current.price} ₸.',
            );
          }
          if (current.price < 1 || current.price > 1000000000) {
            blockers.add('Текущая цена не подтверждена.');
          } else if (current.price > request.budget) {
            blockers.add('Текущая цена выше бюджета категории.');
          }
          if (current.city != event.city) {
            blockers.add('Подрядчик больше не работает в городе события.');
          }
          if (!current.categories.contains(request.category)) {
            blockers.add('Подрядчик больше не работает в этой категории.');
          }
          if (!current.formats.contains(event.format)) {
            blockers.add('Подрядчик не работает с форматом события.');
          }
          if (request.language != null &&
              !current.languages.contains(request.language)) {
            blockers.add('Выбранный язык больше не поддерживается.');
          }
          if (request.hours != null &&
              current.maxHours != null &&
              current.maxHours! < request.hours!) {
            blockers.add('Подрядчик не подходит по длительности.');
          }
          final calendar = calendars[snapshot.id];
          final availability = calendar?.ownerId == snapshot.id
              ? calendar!.availabilityOn(event.date, now)
              : AvailabilityStatus.unconfirmed;
          if (availability == AvailabilityStatus.busy) {
            blockers.add('Дата мероприятия занята.');
          } else if (availability == AvailabilityStatus.unconfirmed) {
            blockers.add('Доступность на дату мероприятия не подтверждена.');
          }
        }
        if (plan.choices.entries.any(
          (entry) =>
              entry.key != request.category &&
              entry.value.contractorId == snapshot.id,
        )) {
          blockers.add('Подрядчик уже выбран в другой категории.');
        }
        final choice = plan.choices[request.category];
        final candidate = PlanCandidate(
          recommendation: recommendation,
          currentContractor: current,
          selectionId: selection.id,
          category: request.category,
          isSelected:
              choice?.selectionId == selection.id &&
              choice?.contractorId == snapshot.id,
          warnings: List.unmodifiable(warnings),
          blockers: List.unmodifiable(blockers),
          draftBrief: buildCandidateBrief(
            event: event,
            selection: selection,
            contractor: current ?? snapshot,
          ),
        );
        candidates.add(candidate);
        if (candidate.isSelected && candidate.canChoose) {
          selected.putIfAbsent(request.category, () => candidate);
        }
      }
      groups.add(
        PlanSelectionReview(
          selection: selection,
          candidates: List.unmodifiable(candidates),
          staleBrief: stale,
        ),
      );
    }
    categories.addAll(plan.choices.keys);
    final unresolved = categories
        .where((category) => !selected.containsKey(category))
        .toList();
    final subtotal = selected.isEmpty
        ? null
        : selected.values.fold<int>(
            0,
            (sum, candidate) => sum + candidate.currentPriceKzt!,
          );
    return EventPlanReview(
      groups: List.unmodifiable(groups),
      selectedCandidates: List.unmodifiable(selected.values),
      unresolvedCategories: List.unmodifiable(unresolved),
      categoryCount: categories.length,
      estimatedFromKzt: subtotal,
      remainingBudgetKzt:
          subtotal != null && unresolved.isEmpty && plan.totalBudgetKzt != null
          ? plan.totalBudgetKzt! - subtotal
          : null,
      exceedsBudget:
          subtotal != null &&
          plan.totalBudgetKzt != null &&
          subtotal > plan.totalBudgetKzt!,
    );
  }
}

/// A copyable draft only. No message is sent and no availability is promised.
String buildCandidateBrief({
  required ClientEvent event,
  required SavedSelection selection,
  required Contractor contractor,
}) {
  final request = selection.request;
  return [
    'Здравствуйте, ${contractor.name}!',
    'Подбираю подрядчика в категории «${request.category}» '
        'для мероприятия «${event.name}».',
    'Дата: ${dateKey(event.date)}. Город: ${event.city}. '
        'Формат: ${event.format}.',
    'Бюджет категории: до ${request.budget} ₸.',
    if (request.hours != null) 'Длительность: ${request.hours} ч.',
    if (request.language != null) 'Язык: ${request.language}.',
    if (event.preferences.trim().isNotEmpty)
      'Пожелания: ${event.preferences.trim()}',
    'Подтвердите, пожалуйста, доступность на эту дату, состав услуг, '
        'итоговую стоимость и условия договора.',
  ].join('\n');
}
