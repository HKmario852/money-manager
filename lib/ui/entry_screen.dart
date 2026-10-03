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
import 'theme.dart';

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
      if (k == 'C') {
        expr = '';
        return;
      }
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

  /// [again] = 「再記一筆」：存完唔離開，清空金額同備註，保留分類、賬戶同日期。
  Future<void> _save({bool again = false}) async {
    final missing = _missing();
    if (missing != null) {
      _toast(missing);
      return;
    }
    setState(() => saving = true);
    try {
      final ledger = ref.read(ledgerProvider);
      final draft = _draft()!;
      final id = await ledger.saveEntry(draft, entryId: widget.existing?.entry.id);
      final paths = ref.read(appPathsProvider);
      for (final src in newPhotos) {
        final name = '${newId()}${p.extension(src)}';
        await File(src).copy(p.join(paths.attachments, name));
        await ledger.addAttachment(id, name, mimeType: 'image/jpeg');
      }
      for (final a in widget.existing?.attachments ?? const <Attachment>[]) {
        if (removedAttachments.contains(a.id)) {
          await ledger.removeAttachment(a.id);
          final f = File(p.join(paths.attachments, p.basename(a.filePath)));
          if (await f.exists()) await f.delete();
        }
      }
      await ledger.db.setSetting(_lastFundKey, fundId!);
      if (!mounted) return;
      if (again) {
        setState(() {
          expr = '';
          note.clear();
          tagIds = {};
          newPhotos.clear();
        });
        _baseline = _snapshot();
        _toast('已記低 ${formatMoney(draft.amount)}，可以再記一筆');
      } else {
        Navigator.pop(context, id);
      }
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
    final kindColor = kind == EntryKind.income ? incomeColor : expenseColor;

    Future<void> pickFund(ValueChanged<String> onPick) async {
      final picked = await pickAccount(context, funds, balances: balances);
      if (picked != null) onPick(picked.id);
    }

    Widget fundButton(String? id, String placeholder, ValueChanged<String> onPick) {
      final a = id != null ? byId[id] : null;
      return _FieldButton(
        icon: a != null ? iconFor(a) : Icons.account_balance_wallet_outlined,
        label: a?.name ?? placeholder,
        onTap: () => pickFund(onPick),
      );
    }

    final category = kind == EntryKind.transfer ? null : byId[categoryId];
    final fund = byId[fundId];
    final subtitle = kind == EntryKind.transfer
        ? '${fund?.name ?? '揀賬戶'} → ${byId[toFundId]?.name ?? '揀賬戶'}'
        : [if (category != null) categoryPath(category, byId), if (fund != null) fund.name].join(' · ');

    final hasOperator = RegExp(r'\d[+-]').hasMatch(expr);
    final shown = expr.isEmpty ? '0' : (hasOperator ? minorToInput(amount ?? 0) : expr);
    final sign = switch (kind) {
      EntryKind.expense => '-',
      EntryKind.income => '+',
      _ => '',
    };

    final existingAtts = (widget.existing?.attachments ?? const <Attachment>[])
        .where((a) => !removedAttachments.contains(a.id))
        .toList();
    final attachmentsDir = ref.watch(appPathsProvider).attachments;
    final selectedTags = tags.where((t) => tagIds.contains(t.id)).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    CircleAction(icon: Icons.close, tooltip: '關閉', onPressed: _confirmLeave),
                    Expanded(
                      child: Center(
                        child: PillSegment<EntryKind>(
                          options: const {EntryKind.expense: '支出', EntryKind.income: '收入', EntryKind.transfer: '轉帳'},
                          value: kind,
                          onChanged: (k) => setState(() {
                            if (k != kind) categoryId = null;
                            kind = k;
                          }),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '更多',
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (v) {
                        if (v == 'template') _saveAsTemplate();
                      },
                      itemBuilder: (_) => const [PopupMenuItem(value: 'template', child: Text('存做模板'))],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  children: [
                    Text(
                      subtitle.isEmpty ? (kind == EntryKind.income ? '揀收入分類' : '揀支出分類') : subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Semantics(
                      label: '金額 ${formatMoney(amount ?? 0)}',
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$sign$moneySymbol ',
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: kindColor),
                                  ),
                                  TextSpan(
                                    text: shown,
                                    style: TextStyle(
                                      fontSize: 52,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1,
                                      color: kindColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (hasOperator) Text(expr, style: const TextStyle(color: AppColors.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (kind == EntryKind.transfer)
                      Row(
                        children: [
                          Expanded(child: fundButton(fundId, '由邊個賬戶', (id) => setState(() => fundId = id))),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward, color: AppColors.muted),
                          ),
                          Expanded(child: fundButton(toFundId, '去邊個賬戶', (id) => setState(() => toFundId = id))),
                        ],
                      )
                    else
                      AppCard(
                        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                        child: _CategoryGrid(
                          categories: topCategories(
                            accounts,
                            kind == EntryKind.income ? AccountType.income : AccountType.expense,
                          ),
                          selectedParentId: categoryId != null ? (byId[categoryId]?.parentId ?? categoryId) : null,
                          onTap: (c) => _pickCategory(c, accounts),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (kind != EntryKind.transfer) ...[
                          Expanded(child: fundButton(fundId, '揀賬戶', (id) => setState(() => fundId = id))),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: _FieldButton(
                            icon: Icons.calendar_today_outlined,
                            label: _dateLabel(date),
                            onTap: _pickDate,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: note,
                      decoration: InputDecoration(
                        hintText: '例如：同事午餐',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 16, right: 10),
                          child: Text(
                            '備註',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(tooltip: 'Tag', icon: const Icon(Icons.tag, size: 20), onPressed: _pickTags),
                            IconButton(
                              tooltip: '影相',
                              icon: const Icon(Icons.photo_camera_outlined, size: 20),
                              onPressed: () => _pickPhoto(ImageSource.camera),
                            ),
                            IconButton(
                              tooltip: '相簿',
                              icon: const Icon(Icons.photo_outlined, size: 20),
                              onPressed: () => _pickPhoto(ImageSource.gallery),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (selectedTags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final t in selectedTags)
                              GestureDetector(
                                onTap: _pickTags,
                                child: Pill('#${t.name}', background: AppColors.card),
                              ),
                          ],
                        ),
                      ),
                    if (existingAtts.isNotEmpty || newPhotos.isNotEmpty)
                      SizedBox(
                        height: 72,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final a in existingAtts)
                              _Thumb(
                                File(p.join(attachmentsDir, p.basename(a.filePath))),
                                onRemove: () => setState(() => removedAttachments.add(a.id)),
                              ),
                            for (final path in newPhotos)
                              _Thumb(File(path), onRemove: () => setState(() => newPhotos.remove(path))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _Keypad(
                onKey: _key,
                onDone: saving ? null : _save,
                onAgain: saving || widget.existing != null ? null : () => _save(again: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dateLabel(DateTime d) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  final rel = switch (days) {
    0 => '今天 ',
    1 => '昨天 ',
    _ => '',
  };
  final y = d.year != now.year ? '${d.year}年' : '';
  return '$rel$y${d.month}月${d.day}日';
}

/// 白色圓角掣（賬戶、日期）。
class _FieldButton extends StatelessWidget {
  const _FieldButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.field),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppColors.inkSoft),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories, required this.selectedParentId, required this.onTap});

  final List<Account> categories;
  final String? selectedParentId;
  final ValueChanged<Account> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: 84),
      children: [
        for (final c in categories)
          Semantics(
            button: true,
            selected: selectedParentId == c.id,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.tile),
              onTap: () => onTap(c),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: selectedParentId == c.id ? AppColors.ink : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: AccountAvatar(c, radius: 22),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selectedParentId == c.id ? FontWeight.w800 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
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

/// 灰底數字鍵盤：右邊係「清除」、「再記一筆」同黑色「完成」。
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey, required this.onDone, required this.onAgain});
  final ValueChanged<String> onKey;
  final VoidCallback? onDone;
  final VoidCallback? onAgain;

  static const _gap = 8.0;
  static const _height = 54.0;

  static const _columns = [
    ['1', '4', '7', '.'],
    ['2', '5', '8', '0'],
    ['3', '6', '9', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    Widget key(String k) => _Key(
      key: ValueKey('key-$k'),
      color: AppColors.card,
      onTap: () => onKey(k),
      onLongPress: k == '⌫' ? () => onKey('C') : null,
      semantics: k == '⌫' ? '刪除' : k,
      child: k == '⌫'
          ? const Icon(Icons.backspace_outlined, color: AppColors.ink)
          : Text(
              k,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: AppColors.ink),
            ),
    );

    return Container(
      color: AppColors.keypadBg,
      padding: const EdgeInsets.fromLTRB(_gap, _gap, _gap, _gap),
      child: Row(
        children: [
          for (final col in _columns) ...[
            Expanded(
              child: Column(
                children: [
                  for (var i = 0; i < col.length; i++) ...[
                    if (i > 0) const SizedBox(height: _gap),
                    SizedBox(height: _height, child: key(col[i])),
                  ],
                ],
              ),
            ),
            const SizedBox(width: _gap),
          ],
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: _height,
                  child: _Key(
                    key: const ValueKey('key-clear'),
                    color: AppColors.keyGrey,
                    onTap: () => onKey('C'),
                    semantics: '清除',
                    child: const Text(
                      '清除',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ),
                ),
                const SizedBox(height: _gap),
                SizedBox(
                  height: _height,
                  child: _Key(
                    key: const ValueKey('key-again'),
                    color: AppColors.keyGrey,
                    onTap: onAgain,
                    semantics: '再記一筆',
                    child: Text(
                      '再記一筆',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: onAgain == null ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: _gap),
                SizedBox(
                  height: _height * 2 + _gap,
                  child: _Key(
                    key: const ValueKey('key-done'),
                    color: AppColors.ink,
                    onTap: onDone,
                    semantics: '完成',
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check, color: AppColors.lime),
                        SizedBox(height: 4),
                        Text(
                          '完成',
                          style: TextStyle(color: AppColors.lime, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    super.key,
    required this.color,
    required this.onTap,
    required this.semantics,
    required this.child,
    this.onLongPress,
  });
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String semantics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Center(child: child),
        ),
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
