import 'package:flutter/material.dart';
import '../../domain/favorites.dart';
import '../../domain/models.dart';
import '../favorites_controller.dart';

String favoriteError(Object error) => error is ArgumentError
    ? error.message.toString()
    : 'Не удалось сохранить изменения. Попробуйте ещё раз.';

class FavoriteFolderPicker extends StatefulWidget {
  const FavoriteFolderPicker({
    super.key,
    required this.controller,
    required this.contractor,
    this.request,
  });
  final FavoritesController controller;
  final Contractor contractor;
  final MatchRequest? request;
  @override
  State<FavoriteFolderPicker> createState() => _FavoriteFolderPickerState();
}

class _FavoriteFolderPickerState extends State<FavoriteFolderPicker> {
  late final name = TextEditingController(
    text: suggestedFolderName(widget.request),
  );
  String? error;
  bool busy = false;

  Future<void> save(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = favoriteError(e);
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final disabled =
          busy ||
          controller.loading ||
          controller.saving ||
          controller.loadError != null;
      final folders = [...controller.folders]
        ..sort((a, b) {
          final target = folderContext(widget.request);
          if ((a.contextKey == target) != (b.contextKey == target)) {
            return a.contextKey == target ? -1 : 1;
          }
          return a.name.compareTo(b.name);
        });
      return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: const Text('Сохранить в избранное'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.contractor.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Выберите папку или создайте новую. Папки сохраняются на этом устройстве.',
                  ),
                  if (controller.loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                  if (controller.loadError != null) ...[
                    const SizedBox(height: 12),
                    Text(controller.loadError!),
                    TextButton(
                      onPressed: controller.load,
                      child: const Text('Повторить загрузку'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  for (final folder in folders) ...[
                    Builder(
                      builder: (context) {
                        final saved = folder.entries.any(
                          (e) => e.contractorId == widget.contractor.id,
                        );
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            key: ValueKey('save-folder-${folder.id}'),
                            leading: Icon(
                              saved ? Icons.favorite : Icons.folder_outlined,
                            ),
                            title: Text(folder.name),
                            subtitle: Text(
                              saved
                                  ? 'Сохранено · нажмите, чтобы убрать'
                                  : contractorCount(folder.entries.length),
                            ),
                            trailing: Icon(saved ? Icons.check : Icons.add),
                            onTap: disabled
                                ? null
                                : () => save(
                                    () => saved
                                        ? controller.remove(
                                            folder.id,
                                            widget.contractor.id,
                                          )
                                        : controller.add(
                                            folder.id,
                                            widget.contractor,
                                            widget.request,
                                          ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('favorite-folder-name'),
                    controller: name,
                    maxLength: 80,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    enabled: !disabled,
                    decoration: const InputDecoration(
                      labelText: 'Новая папка',
                      helperText: 'Название можно изменить',
                      helperMaxLines: 3,
                    ),
                    onSubmitted: disabled
                        ? null
                        : (_) => save(
                            () => controller.createAndSave(
                              name.text,
                              widget.contractor,
                              widget.request,
                            ),
                          ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    key: const Key('create-favorite-folder'),
                    onPressed: disabled
                        ? null
                        : () => save(
                            () => controller.createAndSave(
                              name.text,
                              widget.contractor,
                              widget.request,
                            ),
                          ),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: Text(busy ? 'Сохраняем…' : 'Создать и сохранить'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    },
  );
}
