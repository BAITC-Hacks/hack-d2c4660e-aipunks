import 'package:event_match/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../domain/workspace_models.dart';

/// Content only: the account shell owns navigation, safe areas and scrolling.
class WorkspaceHeading extends StatelessWidget {
  const WorkspaceHeading(this.title, this.subtitle, {super.key});
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class WorkspaceCard extends StatelessWidget {
  const WorkspaceCard({
    super.key,
    required this.child,
    this.color = AppColors.white,
  });
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: color,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  );
}

class WorkspaceEmpty extends StatelessWidget {
  const WorkspaceEmpty({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => WorkspaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 32, color: AppColors.primary)),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class WorkspaceNotice extends StatelessWidget {
  const WorkspaceNotice(this.message, {super.key, this.error = false});
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: WorkspaceCard(
      color: error ? AppColors.peach : AppColors.blue,
      child: Text(message),
    ),
  );
}

class WorkspaceStatus extends StatelessWidget {
  const WorkspaceStatus(this.label, {super.key, this.positive = false});
  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(
      positive ? Icons.check_circle_outline : Icons.info_outline,
      size: 18,
    ),
    label: Text(label),
    backgroundColor: positive ? AppColors.sage : AppColors.lavender,
  );
}

/// Resubscribes on explicit retry, so permission/network failures never masquerade
/// as an empty collection. Parent widgets should supply stable stream instances.
class WorkspaceStream<T> extends StatefulWidget {
  const WorkspaceStream({
    super.key,
    required this.create,
    required this.builder,
  });
  final Stream<T> Function() create;
  final Widget Function(BuildContext, T) builder;

  @override
  State<WorkspaceStream<T>> createState() => _WorkspaceStreamState<T>();
}

class _WorkspaceStreamState<T> extends State<WorkspaceStream<T>> {
  late Stream<T> _stream = widget.create();

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: _stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return WorkspaceEmpty(
          title: 'Не удалось загрузить данные',
          message: 'Проверьте подключение и права доступа. Данные не потеряны.',
          icon: Icons.cloud_off_outlined,
          action: OutlinedButton.icon(
            onPressed: () => setState(() => _stream = widget.create()),
            icon: const Icon(Icons.refresh),
            label:  Text(tr(context, 'Повторить')),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      // Nullable T is legitimate (a contractor profile may not exist yet).
      return widget.builder(context, snapshot.data as T);
    },
  );
}

class WorkspaceAction extends StatefulWidget {
  const WorkspaceAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.check,
    this.successMessage,
    this.outlined = false,
  });
  final String label;
  final Future<void> Function()? onPressed;
  final IconData icon;
  final String? successMessage;
  final bool outlined;

  @override
  State<WorkspaceAction> createState() => _WorkspaceActionState();
}

class _WorkspaceActionState extends State<WorkspaceAction> {
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPressed!();
      if (mounted && widget.successMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(widget.successMessage!)));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is StateError
              ? error.message
              : error is ArgumentError
              ? error.message?.toString() ?? 'Проверьте введённые данные.'
              : 'Не удалось сохранить. Проверьте подключение и повторите. '
                    'Если данные изменились, обновите страницу.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon);
    final callback = _busy || widget.onPressed == null ? null : _run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.outlined)
          OutlinedButton.icon(
            onPressed: callback,
            icon: icon,
            label: Text(_busy ? 'Сохраняем…' : widget.label),
          )
        else
          FilledButton.icon(
            onPressed: callback,
            icon: icon,
            label: Text(_busy ? 'Сохраняем…' : widget.label),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(liveRegion: true, child: Text(_error!)),
          ),
      ],
    );
  }
}

String workspaceDate(DateTime? value) => value == null
    ? 'Ещё не подтверждён'
    : '${value.day.toString().padLeft(2, '0')}.'
          '${value.month.toString().padLeft(2, '0')}.${value.year}';

class ProfileContentDetails extends StatelessWidget {
  const ProfileContentDetails(this.content, {super.key});
  final ProfileContent content;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        content.name.isEmpty ? 'Название не заполнено' : content.name,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      Text('${content.city} · от ${content.price} ₸'),
      const SizedBox(height: 8),
      Text('Категории: ${content.categories.join(', ')}'),
      Text('Форматы: ${content.formats.join(', ')}'),
      Text('Языки: ${content.languages.join(', ')}'),
      Text(
        content.maxHours == null
            ? 'Без ограничения по часам'
            : 'Длительность: до ${content.maxHours} ч',
      ),
      const SizedBox(height: 12),
      Text(
        content.description.isEmpty
            ? 'Описание не заполнено'
            : content.description,
      ),
      if (content.contact.isNotEmpty) ...[
        const SizedBox(height: 12),
        SelectableText('Деловые контакты: ${content.contact}'),
      ],
      for (final url in content.portfolioUrls)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SelectableText(url),
        ),
    ],
  );
}

String profileStatusLabel(String status) => switch (status) {
  'pending' => 'На проверке',
  'approved' => 'Карточка проверена',
  'changes_requested' => 'Нужны исправления',
  _ => 'Черновик',
};

Future<String?> workspaceReason(BuildContext context, String title) async {
  final controller = TextEditingController();
  final key = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            decoration:  InputDecoration(labelText: trNullable(context, 'Причина')),
            validator: localizeValidator(context, (value) => (value ?? '').trim().isEmpty
                ? 'Укажите причину изменения'
                : null),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:  Text(tr(context, 'Отмена')),
        ),
        FilledButton(
          onPressed: () {
            if (key.currentState!.validate()) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child:  Text(tr(context, 'Подтвердить')),
        ),
      ],
    ),
  );
  // The closing route animation can still reference its controller.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}
