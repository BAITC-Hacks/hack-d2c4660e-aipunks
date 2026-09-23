import 'package:flutter/material.dart';
import '../../workspace/domain/workspace_repository.dart';
import '../data/firebase_auth_gateway.dart';
import 'auth_pages.dart';
import 'session_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.session,
    required this.repository,
  });
  final SessionController session;
  final WorkspaceRepository repository;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.session.account?.name ?? widget.session.identity?.name ?? '',
  );
  bool _busy = false;
  String? _error;
  String? _message;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate({bool deletion = false}) async {
    if (widget.session.isAdmin) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          deletion ? 'Запросить удаление данных?' : 'Деактивировать аккаунт?',
        ),
        content: Text(
          deletion
              ? 'Аккаунт будет деактивирован, карточка подрядчика скрыта. Команда Event Match получит запрос на удаление всех данных аккаунта. Обработка выполняется служебным инструментом.'
              : 'Вы потеряете доступ к кабинетам, а карточка подрядчика будет скрыта. Для восстановления понадобится обратиться к команде Event Match.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(deletion ? 'Отправить запрос' : 'Деактивировать'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(
      () => widget.repository.deactivateAccount(
        widget.session.uid!,
        requestDeletion: deletion,
      ),
      'Аккаунт деактивирован.',
    );
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 680),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Настройки аккаунта',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text('Общие для кабинетов заказчика и подрядчика.'),
        const SizedBox(height: 24),
        if (_error != null) AuthNotice(message: _error!, error: true),
        if (_message != null) AuthNotice(message: _message!),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Личные данные',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Имя'),
                    autofillHints: const [AutofillHints.name],
                    validator: (s) => s == null || s.trim().isEmpty
                        ? 'Введите имя'
                        : s.trim().length > 100
                        ? 'Не больше 100 символов'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text('Email: ${widget.session.identity?.email ?? ''}'),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.verified_outlined, size: 20),
                      SizedBox(width: 8),
                      Expanded(child: Text('Email подтверждён')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (!_form.currentState!.validate()) return;
                            _run(() async {
                              await widget.repository.updateName(
                                widget.session.uid!,
                                _name.text.trim(),
                              );
                              await widget.session.auth.updateName(
                                _name.text.trim(),
                              );
                            }, 'Имя сохранено.');
                          },
                    child: Text(_busy ? 'Сохраняем…' : 'Сохранить имя'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.session.auth.resetPassword(
                              widget.session.identity!.email,
                            ),
                            'Письмо для изменения пароля отправлено.',
                          ),
                    child: const Text('Получить ссылку для смены пароля'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Управление аккаунтом',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (widget.session.isAdmin)
                  const Text(
                    'Аккаунт администратора защищён от деактивации и удаления. Сначала передайте управление другому администратору и снимите свою служебную роль доверенным инструментом. После этого здесь появятся действия управления аккаунтом.',
                  )
                else ...[
                  const Text(
                    'Деактивация скрывает профиль и закрывает доступ к кабинетам. Для полного удаления отправьте отдельный запрос.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _deactivate(),
                    child: const Text('Деактивировать аккаунт'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _deactivate(deletion: true),
                    child: const Text('Запросить удаление всех данных'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
