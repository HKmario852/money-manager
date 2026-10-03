import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'accounts_screen.dart';
import 'common.dart';

/// 分類管理：支出 / 收入分頁，拖拉排序，加子分類，改圖示顏色，封存。
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('分類'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '支出'),
              Tab(text: '收入'),
            ],
          ),
        ),
        body: const TabBarView(children: [_CategoryList(AccountType.expense), _CategoryList(AccountType.income)]),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList(this.type);
  final AccountType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(accountsProvider).value ?? const <Account>[];
    final tops = topCategories(all, type);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'cat-$type',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryEditScreen(type: type))),
        icon: const Icon(Icons.add),
        label: const Text('主分類'),
      ),
      body: ReorderableListView(
        buildDefaultDragHandles: true,
        padding: const EdgeInsets.only(bottom: 96),
        onReorderItem: (oldIndex, newIndex) {
          final ids = tops.map((a) => a.id).toList();
          ids.insert(newIndex, ids.removeAt(oldIndex));
          ref.read(ledgerProvider).reorder(ids);
        },
        children: [
          for (final c in tops)
            ExpansionTile(
              key: ValueKey(c.id),
              leading: AccountAvatar(c),
              title: Text(c.name),
              subtitle: Text(
                childrenOf(all, c.id).map((x) => x.name).join('、'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                for (final sub in childrenOf(all, c.id))
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 72, right: 16),
                    leading: AccountAvatar(sub, radius: 14),
                    title: Text(sub.name),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryEditScreen(type: type, category: sub),
                      ),
                    ),
                  ),
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  leading: const Icon(Icons.add),
                  title: const Text('新增子分類'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CategoryEditScreen(type: type, parent: c),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  leading: const Icon(Icons.edit),
                  title: Text('編輯「${c.name}」'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CategoryEditScreen(type: type, category: c),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class CategoryEditScreen extends ConsumerStatefulWidget {
  const CategoryEditScreen({super.key, required this.type, this.category, this.parent});
  final AccountType type;
  final Account? category;
  final Account? parent;

  @override
  ConsumerState<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends ConsumerState<CategoryEditScreen> {
  late final name = TextEditingController(text: widget.category?.name ?? '');
  late String icon = widget.category?.icon ?? widget.parent?.icon ?? 'more';
  late int color = widget.category?.color ?? widget.parent?.color ?? kPalette[0];

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = name.text.trim();
    if (n.isEmpty) return showError(context, '請輸入名稱');
    final ledger = ref.read(ledgerProvider);
    try {
      if (widget.category != null) {
        await ledger.updateAccount(
          widget.category!.id,
          AccountsCompanion(name: Value(n), icon: Value(icon), color: Value(color)),
        );
      } else {
        await ledger.createCategory(name: n, type: widget.type, parentId: widget.parent?.id, icon: icon, color: color);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    return Scaffold(
      appBar: AppBar(
        title: Text(c != null ? '編輯分類' : (widget.parent != null ? '新增「${widget.parent!.name}」子分類' : '新增分類')),
        actions: [
          if (c != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, '刪除或封存「${c.name}」？', message: '用過嘅分類會封存（舊記錄保留）；未用過就直接刪除。')) return;
                await ref.read(ledgerProvider).archiveOrDelete(c.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            autofocus: c == null,
            decoration: const InputDecoration(labelText: '名稱'),
          ),
          const SizedBox(height: 16),
          Text('圖示', style: Theme.of(context).textTheme.titleSmall),
          IconPicker(selected: icon, color: Color(color), onChanged: (v) => setState(() => icon = v)),
          const SizedBox(height: 8),
          Text('顏色', style: Theme.of(context).textTheme.titleSmall),
          ColorPicker(selected: color, onChanged: (v) => setState(() => color = v)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('儲存')),
        ],
      ),
    );
  }
}

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider);
    final ledger = ref.read(ledgerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tag')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final v = await promptText(context, '新 Tag', hint: '例如 去旅行');
          if (v != null && v.trim().isNotEmpty) await ledger.createTag(v);
        },
        child: const Icon(Icons.add),
      ),
      body: asyncBody(tags, (list) {
        if (list.isEmpty) return const EmptyState('未有 Tag。記賬時可以直接新增。', icon: Icons.tag);
        return ListView(
          children: [
            for (final t in list)
              ListTile(
                leading: const Icon(Icons.tag),
                title: Text(t.name),
                subtitle: const Text('改名做已有嘅 Tag 會自動合併'),
                onTap: () async {
                  final v = await promptText(context, '改名', initial: t.name);
                  if (v != null && v.trim().isNotEmpty) await ledger.renameTag(t.id, v);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirm(context, '刪除 #${t.name}？', message: '交易唔會刪除，只會拎走呢個 Tag。', ok: '刪除')) {
                      await ledger.deleteTag(t.id);
                    }
                  },
                ),
              ),
          ],
        );
      }),
    );
  }
}

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);
    final accounts = ref.watch(accountMapProvider);
    final ledger = ref.read(ledgerProvider);
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('常用模板')),
      body: asyncBody(templates, (list) {
        if (list.isEmpty) {
          return const EmptyState('記賬畫面右上角「存做模板」，之後喺首頁一撳即記。', icon: Icons.bolt);
        }
        return ReorderableListView(
          onReorderItem: (oldIndex, newIndex) async {
            final ids = list.map((t) => t.id).toList();
            ids.insert(newIndex, ids.removeAt(oldIndex));
            await db.transaction(() async {
              for (var i = 0; i < ids.length; i++) {
                await (db.update(
                  db.templates,
                )..where((t) => t.id.equals(ids[i]))).write(TemplatesCompanion(sortOrder: Value(i)));
              }
            });
          },
          children: [
            for (final t in list)
              ListTile(
                key: ValueKey(t.id),
                leading: accounts[t.toAccountId] != null ? AccountAvatar(accounts[t.toAccountId]!) : null,
                title: Text(t.name),
                subtitle: Text('${accounts[t.fromAccountId]?.name ?? '?'} → ${accounts[t.toAccountId]?.name ?? '?'}'),
                onTap: () async {
                  final v = await promptText(
                    context,
                    '金額',
                    initial: minorToInput(t.amount),
                    keyboard: const TextInputType.numberWithOptions(decimal: true),
                  );
                  final amt = v == null ? null : parseMinor(v.trim());
                  if (amt != null && amt > 0) {
                    await (db.update(
                      db.templates,
                    )..where((x) => x.id.equals(t.id))).write(TemplatesCompanion(amount: Value(amt)));
                  }
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatMoney(t.amount)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(context, '刪除模板「${t.name}」？', ok: '刪除')) {
                          await ledger.deleteTemplate(t.id);
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}
