import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/design_tokens.dart';
import '../data/firebase_auth_gateway.dart';
import '../domain/auth_gateway.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.auth,
    this.returnTo = '/client/events',
  });
  final AuthGateway auth;
  final String returnTo;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _reset = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? message}) async {
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

  void _submit() {
    if (!_form.currentState!.validate()) return;
    if (_reset) {
      _run(
        () => widget.auth.resetPassword(_email.text),
        message:
            'Если аккаунт с таким email существует, на него отправлено письмо для восстановления.',
      );
    } else if (_register) {
      _run(() => widget.auth.register(_email.text, _password.text, _name.text));
    } else {
      _run(() => widget.auth.signIn(_email.text, _password.text));
    }
  }

  @override
  Widget build(BuildContext context) => AuthFrame(
    title: _reset
        ? 'Восстановить пароль'
        : _register
        ? 'Создать аккаунт'
        : 'С возвращением',
    subtitle: _reset
        ? 'Отправим ссылку на вашу почту.'
        : 'Один аккаунт для ваших мероприятий и работы подрядчиком.',
    child: AutofillGroup(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_register && !_reset) ...[
              TextFormField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(labelText: 'Как вас зовут'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Введите имя'
                    : value.trim().length > 100
                    ? 'Не больше 100 символов'
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              key: const Key('auth-email'),
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) =>
                  value == null ||
                      !RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch(value.trim())
                  ? 'Введите корректный email'
                  : null,
            ),
            if (!_reset) ...[
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('auth-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                autofillHints: [
                  _register
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  helperText: _register ? 'Не менее 8 символов' : null,
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Показать пароль' : 'Скрыть пароль',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Введите пароль'
                    : _register && value.length < 8
                    ? 'Не менее 8 символов'
                    : null,
                onFieldSubmitted: (_) {
                  if (!_busy) _submit();
                },
              ),
            ],
            const SizedBox(height: 20),
            if (_error != null) AuthNotice(message: _error!, error: true),
            if (_message != null) AuthNotice(message: _message!),
            FilledButton(
              key: const Key('auth-submit'),
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy
                    ? 'Подождите…'
                    : _reset
                    ? 'Отправить ссылку'
                    : _register
                    ? 'Создать аккаунт'
                    : 'Войти',
              ),
            ),
            if (!_reset) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(widget.auth.signInWithGoogle),
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('Продолжить с Google'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _register = !_register;
                        _error = null;
                        _message = null;
                      }),
                child: Text(
                  _register
                      ? 'Уже есть аккаунт? Войти'
                      : 'Нет аккаунта? Создать',
                ),
              ),
              if (!_register)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _reset = true;
                          _error = null;
                          _message = null;
                        }),
                  child: const Text('Забыли пароль?'),
                ),
            ] else
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _reset = false;
                        _error = null;
                        _message = null;
                      }),
                child: const Text('Вернуться ко входу'),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => context.go('/'),
              child: const Text('Продолжить просмотр каталога'),
            ),
          ],
        ),
      ),
    ),
  );
}

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({
    super.key,
    required this.auth,
    required this.onRefresh,
  });
  final AuthGateway auth;
  final Future<void> Function() onRefresh;
  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _busy = false;
  String? _message;
  String? _error;
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

  @override
  Widget build(BuildContext context) => AuthFrame(
    title: 'Подтвердите почту',
    subtitle:
        'Откройте письмо на ${widget.auth.currentIdentity?.email ?? 'вашей почте'} и перейдите по ссылке. Это нужно для сохранения мероприятий и публикации профиля.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_message != null) AuthNotice(message: _message!),
        if (_error != null) AuthNotice(message: _error!, error: true),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                  widget.onRefresh,
                  'Проверили статус. Если письмо ещё не подтверждено, перейдите по ссылке и повторите.',
                ),
          child: Text(_busy ? 'Проверяем…' : 'Я подтвердил(а) почту'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(
                  widget.auth.sendVerification,
                  'Письмо отправлено повторно. Проверьте также папку «Спам».',
                ),
          child: const Text('Отправить письмо ещё раз'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(widget.auth.signOut, 'Вы вышли из аккаунта.'),
          child: const Text('Войти в другой аккаунт'),
        ),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Вернуться в каталог'),
        ),
      ],
    ),
  );
}

class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextButton(
        onPressed: () => context.go('/'),
        child: const Text('Event Match'),
      ),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: CircleAvatar(
                        backgroundColor: AppColors.lavender,
                        radius: 28,
                        child: Icon(
                          Icons.person_outline,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(subtitle),
                    const SizedBox(height: 28),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthNotice extends StatelessWidget {
  const AuthNotice({super.key, required this.message, this.error = false});
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error
            ? Theme.of(context).colorScheme.errorContainer
            : AppColors.sage,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error
              ? Theme.of(context).colorScheme.onErrorContainer
              : AppColors.ink,
        ),
      ),
    ),
  );
}
