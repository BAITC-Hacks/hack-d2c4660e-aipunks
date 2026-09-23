import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/design_tokens.dart';
import '../domain/workspace_models.dart';
import '../domain/workspace_repository.dart';
import 'workspace_widgets.dart';

class ContractorPage extends StatefulWidget {
  const ContractorPage({
    super.key,
    required this.repository,
    required this.uid,
    this.section = 'overview',
  });
  final WorkspaceRepository repository;
  final String uid, section;

  @override
  State<ContractorPage> createState() => _ContractorPageState();
}

class _ContractorPageState extends State<ContractorPage> {
  late Future<(ContractorProfile?, PublishedProfile?)> _data = _load();

  Future<(ContractorProfile?, PublishedProfile?)> _load() async {
    final result = await Future.wait<Object?>([
      widget.repository.getProfile(widget.uid),
      widget.repository.getPublished(widget.uid),
    ]);
    return (result[0] as ContractorProfile?, result[1] as PublishedProfile?);
  }

  void _refresh() => setState(() {
    _data = _load();
  });

  Future<void> _change(Future<void> Function() operation) async {
    await operation();
    if (mounted) _refresh();
  }

  @override
  void didUpdateWidget(covariant ContractorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section ||
        oldWidget.uid != widget.uid ||
        oldWidget.repository != widget.repository) {
      _data = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return WorkspaceEmpty(
          title: 'Профиль не загрузился',
          message: 'Проверьте подключение и повторите загрузку.',
          action: OutlinedButton(
            onPressed: _refresh,
            child:  Text(tr(context, 'Повторить')),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final (profile, published) = snapshot.requireData;
      if (widget.section == 'calendar') {
        return _CalendarEditor(
          key: ValueKey(widget.uid),
          repository: widget.repository,
          uid: widget.uid,
          hasProfile: profile != null,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: switch (widget.section) {
          'profile' => [
            const WorkspaceHeading(
              'Мой профиль',
              'Расскажите об услугах. Публичными станут только проверенные данные.',
            ),
            if (profile?.isPending ?? false) ...[
              const WorkspaceNotice(
                'Эта версия отправлена на проверку и зафиксирована. '
                'Чтобы изменить её, сначала отзовите заявку.',
              ),
              WorkspaceCard(child: ProfileContentDetails(profile!.content)),
              _withdraw(),
            ] else ...[
              if (profile?.reason.isNotEmpty ?? false)
                WorkspaceNotice('Замечания модератора: ${profile!.reason}'),
              _ProfileEditor(
                key: ValueKey('${widget.uid}-${profile?.revision ?? 0}'),
                initial: profile?.content ?? const ProfileContent(),
                onSave: (content) => _change(
                  () => widget.repository.saveProfile(widget.uid, content),
                ),
              ),
              if (profile != null) ...[
                const SizedBox(height: 16),
                _submit(profile),
              ],
            ],
          ],
          'moderation' => [
            _refreshButton(),
            const WorkspaceHeading(
              'Проверка профиля',
              'Проверка карточки подтверждает полноту данных, а не гарантирует качество услуг.',
            ),
            if (profile == null)
              _startProfile()
            else ...[
              WorkspaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WorkspaceStatus(
                      profileStatusLabel(profile.status),
                      positive: profile.status == 'approved',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Версия ${profile.revision} · ${workspaceDate(profile.updatedAt)}',
                    ),
                    if (profile.reason.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Комментарий: ${profile.reason}'),
                    ],
                    const SizedBox(height: 16),
                    ProfileContentDetails(profile.content),
                  ],
                ),
              ),
              if (profile.isPending) _withdraw() else _submit(profile),
            ],
            const SizedBox(height: 24),
            _publication(published),
          ],
          _ => [
            _refreshButton(),
            const WorkspaceHeading(
              'Кабинет подрядчика',
              'Профиль и свежий календарь помогают клиентам найти ваши услуги.',
            ),
            if (profile == null)
              _startProfile()
            else ...[
              WorkspaceCard(
                color: AppColors.lavender,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.content.name.isEmpty
                          ? 'Ваш профиль'
                          : profile.content.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const WorkspaceStatus(
                          'Email подтверждён',
                          positive: true,
                        ),
                        WorkspaceStatus(
                          profileStatusLabel(profile.status),
                          positive: profile.status == 'approved',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile.isPending
                          ? 'Заявка на проверке. Календарь можно обновлять уже сейчас.'
                          : profile.content.issues.isNotEmpty
                          ? 'До отправки: ${profile.content.issues.join('; ')}.'
                          : profile.status == 'changes_requested'
                          ? 'Исправьте замечания: ${profile.reason}'
                          : 'Проверьте информацию и актуальность календаря.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.go('/contractor/profile'),
                          icon: const Icon(Icons.edit_outlined),
                          label:  Text(tr(context, 'Открыть профиль')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/contractor/calendar'),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label:  Text(tr(context, 'Подтвердить календарь')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            _publication(published),
            const WorkspaceNotice(
              'Для участия в подборе подтвердите месяц мероприятия. '
              'Подтверждение действует 30 дней; затем доступность нужно обновить.',
            ),
          ],
        },
      );
    },
  );

  Widget _startProfile() => WorkspaceEmpty(
    title: 'Предлагайте услуги с этого аккаунта',
    message:
        'Создайте одну карточку со всеми вашими категориями услуг. '
        'После проверки она появится в живом каталоге.',
    icon: Icons.storefront_outlined,
    action: widget.section == 'profile'
        ? null
        : OutlinedButton(
            onPressed: () => context.go('/contractor/profile'),
            child:  Text(tr(context, 'Заполнить профиль')),
          ),
  );

  Widget _refreshButton() => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      onPressed: _refresh,
      icon: const Icon(Icons.refresh),
      label:  Text(tr(context, 'Обновить статус')),
    ),
  );

  Widget _withdraw() => WorkspaceAction(
    label: 'Отозвать и редактировать',
    icon: Icons.edit_outlined,
    outlined: true,
    onPressed: () =>
        _change(() => widget.repository.withdrawProfile(widget.uid)),
    successMessage: 'Заявка отозвана. Теперь профиль можно изменить.',
  );

  Widget _submit(ContractorProfile profile) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (profile.content.issues.isNotEmpty)
        WorkspaceNotice(
          'Перед отправкой: ${profile.content.issues.join('; ')}.',
        ),
      if (profile.status != 'approved')
        WorkspaceAction(
          label: 'Отправить сохранённую версию на проверку',
          icon: Icons.send_outlined,
          onPressed: profile.content.issues.isNotEmpty
              ? null
              : () =>
                    _change(() => widget.repository.submitProfile(widget.uid)),
          successMessage: 'Профиль отправлен на проверку.',
        ),
    ],
  );

  Widget _publication(PublishedProfile? published) => WorkspaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Публичная карточка',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          published?.published ?? false
              ? 'Опубликована проверенная версия ${published!.profileRevision}. '
                    'Изменения появятся после повторной проверки.'
              : 'Профиль сейчас не опубликован.',
        ),
        if (published?.published ?? false) ...[
          const SizedBox(height: 16),
          WorkspaceAction(
            label: 'Снять с публикации',
            icon: Icons.visibility_off_outlined,
            outlined: true,
            onPressed: () async {
              final reason = await workspaceReason(
                context,
                'Снять карточку с публикации?',
              );
              if (reason != null) {
                await _change(
                  () => widget.repository.unpublish(
                    widget.uid,
                    widget.uid,
                    reason: reason,
                  ),
                );
              }
            },
          ),
        ],
      ],
    ),
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({
    super.key,
    required this.initial,
    required this.onSave,
  });
  final ProfileContent initial;
  final Future<void> Function(ProfileContent) onSave;
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _price = TextEditingController(
    text: widget.initial.price == 0 ? '' : '${widget.initial.price}',
  );
  late final _hours = TextEditingController(
    text: widget.initial.maxHours?.toString() ?? '',
  );
  late final _description = TextEditingController(
    text: widget.initial.description,
  );
  late final _contact = TextEditingController(text: widget.initial.contact);
  late final _portfolio = TextEditingController(
    text: widget.initial.portfolioUrls.join('\n'),
  );
  late String _city = widget.initial.city;
  late final _categories = widget.initial.categories.toSet();
  late final _formats = widget.initial.formats.toSet();
  late final _languages = widget.initial.languages.toSet();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _price,
      _hours,
      _description,
      _contact,
      _portfolio,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        ProfileContent(
          name: _name.text.trim(),
          city: _city,
          categories: _categories.toList()..sort(),
          price: int.tryParse(_price.text.trim()) ?? 0,
          formats: _formats.toList()..sort(),
          languages: _languages.toList()..sort(),
          maxHours: _hours.text.trim().isEmpty
              ? null
              : double.parse(_hours.text.replaceAll(',', '.')),
          description: _description.text.trim(),
          contact: _contact.text.trim(),
          portfolioUrls: _portfolio.text
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Черновик сохранён.')));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось сохранить. Проверьте подключение и повторите.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _choices(String label, List<String> options, Set<String> selected) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options
                  .map(
                    (option) => FilterChip(
                      label: Text(option),
                      selected: selected.contains(option),
                      onSelected: _busy
                          ? null
                          : (value) => setState(
                              () => value
                                  ? selected.add(option)
                                  : selected.remove(option),
                            ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
    int maxLength = 200,
    String? helper,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextFormField(
      controller: controller,
      minLines: lines,
      maxLines: lines,
      enabled: !_busy,
      maxLength: maxLength,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: trNullable(context, label),
        helperText: trNullable(context, helper),
        helperMaxLines: 3,
      ),
      validator: localizeValidator(context, validator),
    ),
  );

  @override
  Widget build(BuildContext context) => WorkspaceCard(
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text(
            tr(context, 'Можно сохранить незаполненный черновик и вернуться к нему позже.'),
          ),
          const SizedBox(height: 24),
          _field(_name, 'Имя или название компании', maxLength: 120),
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: DropdownButtonFormField<String>(
              initialValue: _city,
              isExpanded: true,
              decoration:  InputDecoration(labelText: trNullable(context, 'Город')),
              items: eventCities
                  .map(
                    (city) => DropdownMenuItem(value: city, child: Text(city)),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _city = value!),
            ),
          ),
          _choices('Категории услуг', contractorCategories, _categories),
          _field(
            _price,
            'Цена от, ₸',
            maxLength: 12,
            keyboardType: TextInputType.number,
            validator: localizeValidator(context, (value) {
              if (value!.trim().isEmpty) return null;
              final amount = int.tryParse(value);
              return amount != null && amount >= 0 && amount <= 1000000000
                  ? null
                  : 'Укажите сумму от 0 до 1 000 000 000 ₸';
            }),
          ),
          _choices('Форматы мероприятий', eventFormats, _formats),
          _choices('Языки работы', eventLanguages, _languages),
          _field(
            _hours,
            'Максимальная длительность, ч',
            maxLength: 6,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            helper: 'Оставьте пустым, если услуга не ограничена часами.',
            validator: localizeValidator(context, (value) {
              if (value!.trim().isEmpty) return null;
              final parsed = double.tryParse(value.replaceAll(',', '.'));
              return parsed == null ||
                      !parsed.isFinite ||
                      parsed <= 0 ||
                      parsed > 48
                  ? 'Введите число часов больше 0 и не больше 48'
                  : null;
            }),
          ),
          _field(_description, 'Описание услуг', lines: 5, maxLength: 5000),
          _field(
            _contact,
            'Деловые контакты',
            lines: 2,
            maxLength: 500,
            helper:
                'Эти данные появятся в каталоге после проверки. Email для входа не публикуется автоматически.',
          ),
          _field(
            _portfolio,
            'Ссылки на портфолио',
            lines: 3,
            maxLength: 2500,
            keyboardType: TextInputType.url,
            helper: 'До пяти HTTPS-ссылок, каждая с новой строки.',
            validator: localizeValidator(context, (value) {
              final urls = value!
                  .split('\n')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty);
              if (urls.length > 5) return 'Можно добавить не более пяти ссылок';
              return urls.any((s) {
                    final uri = Uri.tryParse(s);
                    return s.length > 2048 ||
                        uri == null ||
                        uri.scheme != 'https' ||
                        uri.host.isEmpty;
                  })
                  ? 'Используйте полные ссылки вида https://example.com'
                  : null;
            }),
          ),
          if (_error != null) WorkspaceNotice(_error!, error: true),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_busy ? 'Сохраняем…' : 'Сохранить черновик'),
          ),
        ],
      ),
    ),
  );
}

class _CalendarEditor extends StatefulWidget {
  const _CalendarEditor({
    super.key,
    required this.repository,
    required this.uid,
    required this.hasProfile,
  });
  final WorkspaceRepository repository;
  final String uid;
  final bool hasProfile;
  @override
  State<_CalendarEditor> createState() => _CalendarEditorState();
}

class _CalendarEditorState extends State<_CalendarEditor> {
  late final DateTime _first = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  late DateTime _month = _first;
  CalendarMonth? _stored;
  Set<int> _busyDays = {};
  bool _loading = true, _saving = false, _confirmed = false, _dirty = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _confirmed = false;
    });
    try {
      final data = await widget.repository.getCalendar(widget.uid, _month);
      if (mounted && generation == _generation) {
        setState(() {
          _stored = data;
          _busyDays = data?.busyDays.toSet() ?? {};
          _dirty = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Календарь не загрузился. Повторите попытку.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _changeMonth(DateTime month) async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title:  Text(tr(context, 'Перейти к другому месяцу?')),
          content:  Text(tr(context, 'Изменения занятых дней ещё не сохранены.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:  Text(tr(context, 'Остаться')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child:  Text(tr(context, 'Перейти без сохранения')),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => _month = month);
    await _load();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveCalendar(
        widget.uid,
        CalendarMonth(
          ownerId: widget.uid,
          year: _month.year,
          month: _month.month,
          busyDays: _busyDays.toList()..sort(),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Месяц подтверждён на 30 дней.')),
        );
        await _load();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось подтвердить месяц. Ваши изменения сохранены в форме; повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  String _label(DateTime month) => '${_months[month.month - 1]} ${month.year}';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const WorkspaceHeading(
        'Календарь доступности',
        'Отметьте занятые дни. Подтверждение остальных дней действует 30 дней.',
      ),
      if (!widget.hasProfile)
        const WorkspaceNotice(
          'Сначала сохраните черновик профиля, затем заполните календарь.',
        ),
      WorkspaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<DateTime>(
              key: ValueKey(_month),
              initialValue: _month,
              isExpanded: true,
              decoration:  InputDecoration(labelText: trNullable(context, 'Месяц')),
              items:
                  List.generate(
                        13,
                        (i) => DateTime(_first.year, _first.month + i),
                      )
                      .map(
                        (month) => DropdownMenuItem(
                          value: month,
                          child: Text(_label(month)),
                        ),
                      )
                      .toList(),
              onChanged: _saving
                  ? null
                  : (month) {
                      if (month != null) _changeMonth(month);
                    },
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              WorkspaceStatus(
                _stored?.isFresh(DateTime.now()) ?? false
                    ? 'Подтверждён ${workspaceDate(_stored!.confirmedAt)}'
                    : 'Доступность не подтверждена',
                positive: _stored?.isFresh(DateTime.now()) ?? false,
              ),
              const SizedBox(height: 16),
               Text(
                tr(context, 'Выбранные дни — заняты. Все остальные — доступны по вашему календарю.'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  DateTime(_month.year, _month.month + 1, 0).day,
                  (index) {
                    final day = index + 1;
                    return Semantics(
                      label: '$day, ${_label(_month)}',
                      selected: _busyDays.contains(day),
                      child: FilterChip(
                        label: Text('$day'),
                        selected: _busyDays.contains(day),
                        onSelected:
                            _saving ||
                                !widget.hasProfile ||
                                _error != null && _stored == null
                            ? null
                            : (selected) => setState(() {
                                selected
                                    ? _busyDays.add(day)
                                    : _busyDays.remove(day);
                                _dirty = true;
                                _confirmed = false;
                              }),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmed,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged:
                    _saving ||
                        !widget.hasProfile ||
                        _error != null && _stored == null
                    ? null
                    : (value) => setState(() => _confirmed = value ?? false),
                title:  Text(
                  tr(context, 'Подтверждаю доступность всех неотмеченных дней этого месяца'),
                ),
                subtitle:  Text(
                  tr(context, 'Это информация для подбора, без обещания бронирования.'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _confirmed && !_saving && widget.hasProfile
                    ? _save
                    : null,
                icon: const Icon(Icons.event_available_outlined),
                label: Text(
                  _saving ? 'Подтверждаем…' : 'Сохранить и подтвердить месяц',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              WorkspaceNotice(_error!, error: true),
              if (!_dirty)
                OutlinedButton(
                  onPressed: _load,
                  child:  Text(tr(context, 'Повторить загрузку')),
                ),
            ],
          ],
        ),
      ),
    ],
  );
}
