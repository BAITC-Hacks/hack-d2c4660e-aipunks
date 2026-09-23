import 'package:flutter/material.dart';
import '../domain/favorites.dart';
import '../domain/matching_engine.dart';
import '../domain/models.dart';
import 'favorites_controller.dart';
import 'widgets/contractor_card.dart';
import 'widgets/favorite_folder_picker.dart';
import 'widgets/side_panel.dart';

Future<MatchRequest?> showFavoritesPanel(
  BuildContext context, {
  required FavoritesController controller,
  required List<Contractor> catalog,
  required bool catalogAvailable,
}) => showSidePanel<MatchRequest>(
  context,
  barrierLabel: 'Закрыть избранное',
  builder: (_) => ScaffoldMessenger(
    child: FavoritesPage(
      controller: controller,
      catalog: catalog,
      catalogAvailable: catalogAvailable,
    ),
  ),
);

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    super.key,
    required this.controller,
    required this.catalog,
    this.catalogAvailable = true,
  });
  final FavoritesController controller;
  final List<Contractor> catalog;
  final bool catalogAvailable;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String? selectedFolderId;
  final closeFocus = FocusNode(debugLabel: 'Close favorites panel');
  FavoritesController get controller => widget.controller;
  List<Contractor> get catalog => widget.catalog;
  bool get catalogAvailable => widget.catalogAvailable;

  void close() => Navigator.pop(context);

  void selectFolder(String? folderId) {
    setState(() => selectedFolderId = folderId);
    // The clicked folder/back button disappears with the previous view. Keep
    // keyboard focus inside the modal so Escape and Tab continue to work.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) closeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    closeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (selectedFolderId case final folderId?) {
      return FavoriteFolderPage(
        controller: controller,
        folderId: folderId,
        catalog: catalog,
        catalogAvailable: catalogAvailable,
        onBack: () => selectFolder(null),
        onClose: close,
        closeFocus: closeFocus,
        onRestoreSearch: (request) => Navigator.pop(context, request),
      );
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Избранное'),
        actions: [
          IconButton(
            autofocus: true,
            focusNode: closeFocus,
            tooltip: 'Закрыть избранное',
            onPressed: close,
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (controller.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(
                  key: const PageStorageKey('favorite-folders'),
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Соберите команду для каждого события',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ведущие, фотографы и площадки — в одной папке. Сохранено на этом устройстве.',
                    ),
                    const SizedBox(height: 24),
                    if (controller.loadError != null) ...[
                      Text(controller.loadError!),
                      TextButton(
                        onPressed: controller.load,
                        child: const Text('Повторить загрузку'),
                      ),
                    ] else if (controller.folders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Icon(Icons.favorite_border, size: 48),
                            SizedBox(height: 16),
                            Text(
                              'Пока нет сохранённых подрядчиков',
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Нажмите сердечко на карточке. Мы предложим название папки по вашему поиску.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    for (final folder in controller.folders)
                      Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: InkWell(
                          key: ValueKey('favorite-folder-${folder.id}'),
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => selectFolder(folder.id),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (final category in {
                                      for (final p in catalog.where(
                                        (p) => folder.entries.any(
                                          (e) => e.contractorId == p.id,
                                        ),
                                      ))
                                        p.categories.first,
                                      if (folder.entries.isEmpty ||
                                          !catalogAvailable)
                                        'Папка',
                                    }.take(3))
                                      Container(
                                        width: 64,
                                        height: 64,
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Icon(
                                          category == 'Папка'
                                              ? Icons.folder_outlined
                                              : categoryIcon(category),
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                          size: 30,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  folder.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(contractorCount(folder.entries.length)),
                                if (folder.entries.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    folder.entries
                                        .take(3)
                                        .map((e) => e.name)
                                        .join(' · '),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                const Text('Открыть папку →'),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class FavoriteFolderPage extends StatelessWidget {
  const FavoriteFolderPage({
    super.key,
    required this.controller,
    required this.folderId,
    required this.catalog,
    required this.onBack,
    required this.onClose,
    required this.closeFocus,
    required this.onRestoreSearch,
    this.catalogAvailable = true,
  });
  final FavoritesController controller;
  final String folderId;
  final List<Contractor> catalog;
  final bool catalogAvailable;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final FocusNode closeFocus;
  final ValueChanged<MatchRequest> onRestoreSearch;

  Future<void> change(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(favoriteError(e))));
      }
    }
  }

  Future<void> rename(BuildContext context, FavoriteFolder folder) async {
    var name = folder.name;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название папки'),
        content: TextFormField(
          initialValue: name,
          onChanged: (value) => name = value,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Название'),
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, name),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (value != null && context.mounted) {
      await change(context, () => controller.rename(folder.id, value));
    }
  }

  Future<void> delete(BuildContext context, FavoriteFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить папку?'),
        content: Text(
          '«${folder.name}» и сохранённые в ней ссылки будут удалены с этого устройства.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await change(context, () async {
        await controller.delete(folder.id);
        if (context.mounted) onBack();
      });
    }
  }

  String availability(Contractor contractor, FavoriteEntry entry) {
    final request = entry.request;
    if (request == null) {
      return 'Добавлен из каталога. Дата и условия ещё не выбраны.';
    }
    final evaluations = const MatchingEngine().evaluate([contractor], request);
    if (evaluations.isEmpty) {
      return 'Профиль больше не соответствует сохранённому городу или категории.';
    }
    final reasons = evaluations.single.violations.map(
      (v) => switch (v) {
        Violation.busy => 'занят на дату',
        Violation.budget => 'выше бюджета',
        Violation.format => 'другой формат',
        Violation.language => 'нет нужного языка',
        Violation.hours => 'не хватает часов',
        Violation.unconfirmed => 'календарь не подтверждён',
      },
    );
    return reasons.isEmpty
        ? 'Подходит по сохранённым условиям каталога.'
        : 'По сохранённым условиям: ${reasons.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final folders = controller.folders.where((f) => f.id == folderId);
      final folder = folders.isEmpty ? null : folders.first;
      final byId = {for (final p in catalog) p.id: p};
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'К папкам избранного',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('Папка избранного'),
          actions: [
            if (folder != null)
              PopupMenuButton<String>(
                tooltip: 'Действия с папкой',
                enabled: !controller.saving,
                onSelected: (value) => value == 'rename'
                    ? rename(context, folder)
                    : delete(context, folder),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить папку')),
                ],
              ),
            IconButton(
              autofocus: true,
              focusNode: closeFocus,
              tooltip: 'Закрыть избранное',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                key: PageStorageKey('favorite-folder-$folderId'),
                padding: const EdgeInsets.all(24),
                children: [
                  if (folder != null) ...[
                    Text(
                      folder.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Избранное не бронирует дату. Доступность показана по текущему каталогу.',
                    ),
                    const SizedBox(height: 24),
                    if (folder.entries.isEmpty)
                      const Text(
                        'В папке пока пусто. Добавьте подрядчика сердечком из каталога или подбора.',
                      ),
                    for (final entry in folder.entries) ...[
                      if (byId[entry.contractorId] case final contractor?) ...[
                        ContractorCard(
                          contractor: contractor,
                          isFavorite: true,
                          favoriteTooltip: 'Убрать из этой папки',
                          onFavorite: controller.saving
                              ? null
                              : () => change(
                                  context,
                                  () => controller.remove(
                                    folder.id,
                                    entry.contractorId,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        Text(availability(contractor, entry)),
                      ] else
                        ListTile(
                          title: Text(entry.name),
                          subtitle: Text(
                            catalogAvailable
                                ? 'Профиль больше недоступен в каталоге'
                                : 'Каталог пока недоступен. Вернитесь после его загрузки, чтобы проверить профиль.',
                          ),
                          trailing: IconButton(
                            tooltip: 'Убрать из папки',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: controller.saving
                                ? null
                                : () => change(
                                    context,
                                    () => controller.remove(
                                      folder.id,
                                      entry.contractorId,
                                    ),
                                  ),
                          ),
                        ),
                      if (entry.request case final request?) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${request.city} · ${request.category} · ${request.format} · ${MaterialLocalizations.of(context).formatMediumDate(request.date)} · до ${money(request.budget)} ₸',
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: ValueKey(
                              'restore-search-${entry.contractorId}',
                            ),
                            onPressed: () => onRestoreSearch(request),
                            icon: const Icon(Icons.search),
                            label: const Text('Повторить этот поиск'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
