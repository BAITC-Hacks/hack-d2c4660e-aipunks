import 'package:event_match/l10n/app_localizations.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/local_api.dart';
import '../auth/presentation/session_controller.dart';
import '../matching/domain/models.dart';
import '../matching/presentation/widgets/side_panel.dart';

abstract interface class MessagesRepository {
  Future<List<Map<String, dynamic>>> list();
  Future<Map<String, dynamic>> open(String contractorId);
  Future<List<Map<String, dynamic>>> read(String threadId);
  Future<void> send(String threadId, String text, String nonce);
}

class ApiMessagesRepository implements MessagesRepository {
  ApiMessagesRepository(this.api);
  final LocalApi api;
  Future<dynamic> _call(String op, [Map<String, dynamic> data = const {}]) =>
      api.post('/v1/messages', {'op': op, ...data});
  @override
  Future<List<Map<String, dynamic>>> list() async =>
      (await _call('list') as List).cast<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> open(String contractorId) async =>
      await _call('open', {'contractorId': contractorId})
          as Map<String, dynamic>;
  @override
  Future<List<Map<String, dynamic>>> read(String threadId) async =>
      (await _call('read', {'threadId': threadId}) as List)
          .cast<Map<String, dynamic>>();
  @override
  Future<void> send(String threadId, String text, String nonce) async {
    await _call('send', {'threadId': threadId, 'text': text, 'nonce': nonce});
  }
}

Future<void> showMessagesPanel(
  BuildContext context, {
  required SessionController session,
  required MessagesRepository repository,
  required VoidCallback onSignIn,
  Contractor? contractor,
}) => showSidePanel<void>(
  context,
  barrierLabel: tr(context, 'Закрыть сообщения'),
  builder: (_) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => MessagesPanel(
      key: ValueKey('messages:${session.epoch}'),
      repository: repository,
      uid: session.canUseWorkspace ? session.uid : null,
      contractor: contractor,
      onSignIn: onSignIn,
    ),
  ),
);

class MessagesPanel extends StatefulWidget {
  const MessagesPanel({
    super.key,
    required this.repository,
    required this.uid,
    required this.onSignIn,
    this.contractor,
  });
  final MessagesRepository repository;
  final String? uid;
  final Contractor? contractor;
  final VoidCallback onSignIn;
  @override
  State<MessagesPanel> createState() => _MessagesPanelState();
}

class _MessagesPanelState extends State<MessagesPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  List<Map<String, dynamic>> _threads = [], _messages = [];
  Map<String, dynamic>? _thread;
  bool _loading = false, _sending = false;
  String? _error, _nonce, _pendingText;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.uid != null) {
      unawaited(_initial());
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    }
  }

  Future<void> _initial() async {
    if (widget.contractor?.isLive == true) {
      setState(() => _loading = true);
      try {
        _thread = await widget.repository.open(widget.contractor!.id);
      } catch (e) {
        if (mounted) setState(() => _error = _message(e));
      }
      if (!mounted) return;
      setState(() => _loading = false);
    }
    await _refresh();
  }

  String _message(Object e) => e is LocalApiException
      ? e.message
      : 'Не удалось загрузить сообщения. Повторите попытку.';
  Future<void> _refresh() async {
    if (_loading || widget.uid == null) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final selected = _thread;
      final data = selected == null
          ? await widget.repository.list()
          : await widget.repository.read(selected['id'] as String);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (selected == null) {
          _threads = data;
        } else {
          _messages = data;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _select(Map<String, dynamic> thread) async {
    ++_generation;
    setState(() {
      _thread = thread;
      _messages = [];
      _error = null;
      _loading = false;
      _input.clear();
      _nonce = null;
      _pendingText = null;
    });
    await _refresh();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_sending || text.isEmpty || text.length > 4000 || _thread == null) {
      return;
    }
    final threadId = _thread!['id'] as String;
    final generation = _generation;
    if (_pendingText != text) {
      _nonce = List.generate(
        24,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _pendingText = text;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repository.send(threadId, text, _nonce!);
      if (!mounted) return;
      if (_thread?['id'] == threadId) {
        _input.clear();
        _nonce = null;
        _pendingText = null;
      }
      await _refresh();
    } catch (e) {
      if (mounted &&
          (_generation == generation || _thread?['id'] == threadId)) {
        setState(() => _error = _message(e));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: _thread == null
          ? null
          : IconButton(
              tooltip: trNullable(context, 'Все переписки'),
              onPressed: _sending
                  ? null
                  : () {
                      ++_generation;
                      setState(() {
                        _thread = null;
                        _loading = false;
                        _messages = [];
                        _input.clear();
                      });
                      _refresh();
                    },
              icon: const Icon(Icons.arrow_back),
            ),
      title: Text(
        _thread?['peerName'] as String? ?? 'Сообщения',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          autofocus: true,
          tooltip: trNullable(context, 'Закрыть сообщения'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    body: widget.uid == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.forum_outlined, size: 48),
                  const SizedBox(height: 16),
                   Text(
                    tr(context, 'Войдите, чтобы написать подрядчику и сохранить переписку.'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: widget.onSignIn,
                    child:  Text(tr(context, 'Войти в аккаунт')),
                  ),
                ],
              ),
            ),
          )
        : Column(
            children: [
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(_error!, semanticsLabel: trNullable(context, _error)),
                      TextButton(
                        onPressed: _refresh,
                        child:  Text(tr(context, 'Повторить')),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _thread == null
                    ? _threads.isEmpty && !_loading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Здесь появятся ваши переписки. Нажмите «Написать» в карточке опубликованного подрядчика.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView(
                              children: [
                                for (final t in _threads)
                                  ListTile(
                                    key: ValueKey('thread-${t['id']}'),
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.person_outline),
                                    ),
                                    title: Text(t['peerName'] as String),
                                    subtitle: Text(
                                      t['lastMessage'] as String,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => _select(t),
                                  ),
                              ],
                            )
                    : _messages.isEmpty && !_loading
                    ? const Center(
                        child: Text(
                          'Начните разговор — уточните дату и услуги.',
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.all(20),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[_messages.length - 1 - i],
                              own = m['senderId'] == widget.uid;
                          return Align(
                            alignment: own
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 460),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: own
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: SelectableText(m['text'] as String),
                            ),
                          );
                        },
                      ),
              ),
              if (_thread != null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('message-input'),
                            controller: _input,
                            enabled: !_sending,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 4000,
                            decoration:  InputDecoration(
                              labelText: trNullable(context, 'Сообщение подрядчику'),
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: const Key('send-message'),
                          tooltip: trNullable(context, 'Отправить сообщение'),
                          onPressed: _sending ? null : _send,
                          icon: Icon(
                            _sending
                                ? Icons.hourglass_top
                                : Icons.send_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}
