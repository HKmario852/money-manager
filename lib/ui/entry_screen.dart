import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../domain/ledger.dart';
import '../domain/money.dart';
import '../providers.dart';
import 'common.dart';

const _lastFundKey = 'last_fund_account';

/// 記賬畫面（新增 / 編輯 / 複製）。
class EntryScreen extends ConsumerStatefulWidget {
  const EntryScreen({super.key, this.existing, this.initial});

  /// 編輯緊嘅交易
  final TxView? existing;

  /// 預填（複製一筆、由模板開）
  final EntryDraft? initial;

  @override
  ConsumerState<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends ConsumerState<EntryScreen> {
  EntryKind kind = EntryKind.expense;
  String expr = '';
  String? fundId; // 支出/收入嘅資金賬戶；轉賬嘅「由」
  String? toFundId; // 轉賬嘅「去」
  String? categoryId;
  DateTime date = DateTime.now();
  final note = TextEditingController();
  Set<String> tagIds = {};
  final newPhotos = <String>[];
  final removedAttachments = <String>{};
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final d = widget.initial;
    if (e != null) {
      kind = e.entry.kind;
      expr = minorToInput(e.amount);
      date = e.entry.occurredAt;
      note.text = e.entry.note ?? '';
      tagIds = e.tags.map((t) => t.id).toSet();
      _setAccounts(e.from.id, e.to.id);
    } else if (d != null) {
      kind = d.kind;
      expr = minorToInput(d.amount);
      date = d.occurredAt;
      note.text = d.note ?? '';
      tagIds = d.tagIds.toSet();
      _setAccounts(d.fromAccountId, d.toAccountId);
    } else {
      _loadLastFund();
    }
  }

  void _setAccounts(String from, String to) {
    switch (kind) {
      case EntryKind.income:
        categoryId = from;
        fundId = to;
      case EntryKind.transfer:
        fundId = from;
        toFundId = to;
      default:
        fundId = from;
        categoryId = to;
    }
  }

  Future<void> _loadLastFund() async {
    final id = await ref.read(databaseProvider).getSetting(_lastFundKey);
    if (!mounted) return;
    final accounts = ref.read(accountMapProvider);
    final untouched = !_isDirty;
    setState(() {
      fundId = (id != null && accounts[id]?.isArchived == false) ? id : null;
      fundId ??= fundAccounts(accounts.values).firstOrNull?.id;
    });
    if (untouched) _baseline = _snapshot();
  }

  /// 用嚟判斷用戶有冇改過嘢，有就喺返回時先問一句。
  late String _baseline = _snapshot();

  String _snapshot() => [
    kind,
    expr,
    fundId,
    toFundId,
    categoryId,
    date,
    note.text,
    (tagIds.toList()..sort()).join(','),
    newPhotos.length,
    removedAttachments.length,
  ].join('|');

  bool get _isDirty => _snapshot() != _baseline;

  Future<void> _confirmLeave() async {
    if (_isDirty && !await confirm(context, '唔儲存就離開？', message: '輸入咗嘅內容會冇咗。', ok: '離開')) return;
    if (mounted) Navigator.of(context).pop();
  }

  /// 喺數字鍵盤上面顯示提示，唔好遮住 ✓ 掣。
  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 330),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  int? get amount => evaluateAmount(expr);

  void _key(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '⌫') {
        if (expr.isNotEmpty) expr = expr.substring(0, expr.length - 1);
        return;
      }
      if (k == '+' || k == '-') {
        if (expr.isEmpty) return;
        final last = expr[expr.length - 1];
        if (last == '+' || last == '-') expr = expr.substring(0, expr.length - 1);
        expr += k;
        return;
      }
      final candidate = expr + k;
      // 只容許兩位小數同合理長度
      final lastNumber = candidate.split(RegExp(r'[+-]')).last;
      if (!RegExp(r'^\d{0,9}(\.\d{0,2})?$').hasMatch(lastNumber)) return;
      if (lastNumber.startsWith('0') && lastNumber.length > 1 && !lastNumber.startsWith('0.')) return;
      expr = candidate;
    });
  }

  EntryDraft? _draft() {
    final amt = amount;
    if (amt == null || amt <= 0) return null;
    final (from, to) = switch (kind) {
      EntryKind.income => (categoryId, fundId),
      EntryKind.transfer => (fundId, toFundId),
      _ => (fundId, categoryId),
    };
    if (from == null || to == null) return null;
    return EntryDraft(
      kind: kind,
      amount: amt,
      fromAccountId: from,
      toAccountId: to,
      occurredAt: date,
      note: note.text,
      tagIds: tagIds.toList(),
    );
  }

  String? _missing() {
    final amt = amount;
    if (amt == null || amt <= 0) return '請輸入金額';
    if (kind == EntryKind.transfer) {
      if (fundId == null || toFundId == null) return '請揀兩個賬戶';
      if (fundId == toFundId) return '兩個賬戶唔可以一樣';
    } else {
      if (categoryId == null) return '請揀分類';
      if (fundId == null) return '請揀賬戶';
    }
    return null;
  }

  Future<void> _save() async {
    final missing = _missing();
    if (missing != null) {
      _toast(missing);
      return;
    }
    setState(() => saving = true);
    try {
      final ledger = ref.read(ledgerProvider);
      final id = await ledger.saveEntry(_draft()!, entryId: widget.existing?.entry.id);
      final paths = ref.read(appPathsProvider);
      for (final src in newPhotos) {
        final name = '${newId()}${p.extension(src)}';
        await File(src).copy(p.join(paths.attachments, name));
        await ledger.addAttachment(id, name, mimeType: 'image/jpeg');
      }
      for (final a in widget.existing?.attachments ?? const <Attachment>[]) {
        if (removedAttachments.contains(a.id)) {
          await ledger.removeAttachment(a.id);
          final f = File(p.join(paths.attachments, a.filePath));
          if (await f.exists()) await f.delete();
        }
      }
      await ledger.db.setSetting(_lastFundKey, fundId!);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) _toast(e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _saveAsTemplate() async {
    final missing = _missing();
    if (missing != null) {
      _toast(missing);
      return;
    }
    final accounts = ref.read(accountMapProvider);
    final cat = kind == EntryKind.transfer ? null : accounts[categoryId];
    final name = await promptText(context, '模板名稱', initial: note.text.isNotEmpty ? note.text : (cat?.name ?? '轉賬'));
    if (name == null || name.trim().isEmpty) return;
    await ref.read(ledgerProvider).saveTemplate(name.trim(), _draft()!);
    if (mounted) {
      _toast('已存做模板「${name.trim()}」');
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 2000);
    if (file != null) setState(() => newPhotos.add(file.path));
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(date));
    setState(() => date = DateTime(d.year, d.month, d.day, t?.hour ?? date.hour, t?.minute ?? date.minute));
  }

  Future<void> _pickCategory(Account parent, List<Account> all) async {
    final children = childrenOf(all, parent.id);
    if (children.isEmpty) {
      setState(() => categoryId = parent.id);
      return;
    }
    final picked = await pickAccount(context, [parent, ...children], title: parent.name);
    if (picked != null) setState(() => categoryId = picked.id);
  }

  Future<void> _pickTags() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => _TagPicker(selected: tagIds, onChanged: (s) => setState(() => tagIds = s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final byId = {for (final a in accounts) a.id: a};
    final balances = ref.watch(balancesProvider).value ?? const {};
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final funds = fundAccounts(accounts);
    final theme = Theme.of(context);
    final kindColor = switch (kind) {
      EntryKind.expense => expenseColor,
      EntryKind.income => incomeColor,
      _ => theme.colorScheme.primary,
    };

    Widget fundChip(String label, String? id, ValueChanged<String> onPick) {
      final a = id != null ? byId[id] : null;
      return ActionChip(
        avatar: a != null ? Icon(iconFor(a), size: 18) : const Icon(Icons.account_balance_wallet, size: 18),
        label: Text(a != null ? '$label：${a.name}' : '$label：揀賬戶'),
        onPressed: () async {
          final picked = await pickAccount(context, funds, balances: balances);
          if (picked != null) onPick(picked.id);
        },
      );
    }

    final existingAtts = (widget.existing?.attachments ?? const <Attachment>[])
        .where((a) => !removedAttachments.contains(a.id))
        .toList();
    final attachmentsDir = ref.watch(appPathsProvider).attachments;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: SegmentedButton<EntryKind>(
            segments: const [
              ButtonSegment(value: EntryKind.expense, label: Text('支出')),
              ButtonSegment(value: EntryKind.income, label: Text('收入')),
              ButtonSegment(value: EntryKind.transfer, label: Text('轉賬')),
            ],
            selected: {kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              if (s.first != kind) categoryId = null;
              kind = s.first;
            }),
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'template') _saveAsTemplate();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'template', child: Text('存做模板'))],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  children: [
                    if (kind == EntryKind.transfer) ...[
                      fundChip('由', fundId, (id) => setState(() => fundId = id)),
                      const Center(child: Icon(Icons.arrow_downward)),
                      fundChip('去', toFundId, (id) => setState(() => toFundId = id)),
                    ] else
                      _CategoryGrid(
                        categories: topCategories(
                          accounts,
                          kind == EntryKind.income ? AccountType.income : AccountType.expense,
                        ),
                        selectedId: categoryId,
                        selectedParentId: categoryId != null ? (byId[categoryId]?.parentId ?? categoryId) : null,
                        onTap: (c) => _pickCategory(c, accounts),
                      ),
                    if (kind != EntryKind.transfer && byId[categoryId] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('分類：${categoryPath(byId[categoryId]!, byId)}', style: theme.textTheme.bodyMedium),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (kind != EntryKind.transfer)
                          fundChip(kind == EntryKind.income ? '存入' : '用', fundId, (id) => setState(() => fundId = id)),
                        ActionChip(
                          avatar: const Icon(Icons.event, size: 18),
                          label: Text('${formatDate(date)} ${formatTime(date)}'),
                          onPressed: _pickDate,
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.tag, size: 18),
                          label: Text(
                            tagIds.isEmpty
                                ? 'Tag'
                                : tags.where((t) => tagIds.contains(t.id)).map((t) => '#${t.name}').join(' '),
                          ),
                          onPressed: _pickTags,
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.photo_camera, size: 18),
                          label: const Text('影相'),
                          onPressed: () => _pickPhoto(ImageSource.camera),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.photo_library, size: 18),
                          label: const Text('相簿'),
                          onPressed: () => _pickPhoto(ImageSource.gallery),
                        ),
                      ],
                    ),
                    if (existingAtts.isNotEmpty || newPhotos.isNotEmpty)
                      SizedBox(
                        height: 72,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final a in existingAtts)
                              _Thumb(
                                File(p.join(attachmentsDir, a.filePath)),
                                onRemove: () => setState(() => removedAttachments.add(a.id)),
                              ),
                            for (final path in newPhotos)
                              _Thumb(File(path), onRemove: () => setState(() => newPhotos.remove(path))),
                          ],
                        ),
                      ),
                    TextField(
                      controller: note,
                      decoration: const InputDecoration(hintText: '備註', prefixIcon: Icon(Icons.notes)),
                    ),
                  ],
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: kindColor.withValues(alpha: 0.08),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (RegExp(r'\d[+-]').hasMatch(expr)) Text(expr, style: theme.textTheme.bodySmall),
                    Text(
                      formatMoney(amount ?? 0),
                      style: theme.textTheme.headlineMedium?.copyWith(color: kindColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              _Keypad(onKey: _key, onDone: saving ? null : _save, doneColor: kindColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.selectedId,
    required this.selectedParentId,
    required this.onTap,
  });

  final List<Account> categories;
  final String? selectedId;
  final String? selectedParentId;
  final ValueChanged<Account> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 80, mainAxisExtent: 72),
      children: [
        for (final c in categories)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(c),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: selectedParentId == c.id ? Border.all(color: colorFor(c, context), width: 2) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AccountAvatar(c, radius: 18),
                  const SizedBox(height: 4),
                  Text(c.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.file, {required this.onRemove});
  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(file, width: 60, height: 60, fit: BoxFit.cover),
          ),
          Positioned(
            right: -10,
            top: -10,
            child: IconButton(icon: const Icon(Icons.cancel, size: 20), onPressed: onRemove),
          ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey, required this.onDone, required this.doneColor});
  final ValueChanged<String> onKey;
  final VoidCallback? onDone;
  final Color doneColor;

  static const _rows = [
    ['7', '8', '9', '⌫'],
    ['4', '5', '6', '+'],
    ['1', '2', '3', '-'],
    ['.', '0', '00', '✓'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          for (final row in _rows)
            Row(
              children: [
                for (final k in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: SizedBox(
                        height: 52,
                        child: k == '✓'
                            ? FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: doneColor,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: onDone,
                                child: const Icon(Icons.check),
                              )
                            : FilledButton.tonal(
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  if (k == '00') {
                                    onKey('0');
                                    onKey('0');
                                  } else {
                                    onKey(k);
                                  }
                                },
                                child: k == '⌫'
                                    ? const Icon(Icons.backspace_outlined)
                                    : Text(k == '-' ? '−' : k, style: const TextStyle(fontSize: 22)),
                              ),
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

class _TagPicker extends ConsumerStatefulWidget {
  const _TagPicker({required this.selected, required this.onChanged});
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  ConsumerState<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends ConsumerState<_TagPicker> {
  late Set<String> selected = {...widget.selected};
  final input = TextEditingController();

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (input.text.trim().isEmpty) return;
    try {
      final id = await ref.read(ledgerProvider).createTag(input.text);
      input.clear();
      setState(() => selected.add(id));
      widget.onChanged(selected);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final t in tags)
                  FilterChip(
                    label: Text('#${t.name}'),
                    selected: selected.contains(t.id),
                    onSelected: (v) {
                      setState(() => v ? selected.add(t.id) : selected.remove(t.id));
                      widget.onChanged(selected);
                    },
                  ),
              ],
            ),
            TextField(
              controller: input,
              decoration: InputDecoration(
                hintText: '新 Tag，例如 去旅行',
                prefixText: '#',
                suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _add),
              ),
              onSubmitted: (_) => _add(),
            ),
          ],
        ),
      ),
    );
  }
}
