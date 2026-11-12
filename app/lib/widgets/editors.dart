import 'package:flutter/material.dart';

import '../common.dart';

/// 표 형태 입력 (요구사항, 지표, 개정이력, 결재라인 …). 값: [{key: text}]
class ListEditor extends StatefulWidget {
  const ListEditor({super.key, required this.columns, required this.initial, required this.onChanged, this.hint, this.multilineKeys = const {}});
  final List<(String key, String label, int flex)> columns;
  final List<Map<String, dynamic>> initial;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final String? hint;
  final Set<String> multilineKeys;

  @override
  State<ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<ListEditor> {
  late List<Map<String, TextEditingController>> rows;

  @override
  void initState() {
    super.initState();
    rows = [for (final r in widget.initial) _ctl(r)];
  }

  Map<String, TextEditingController> _ctl(Map<String, dynamic> r) =>
      {for (final c in widget.columns) c.$1: TextEditingController(text: txt(r[c.$1]))};

  @override
  void dispose() {
    for (final r in rows) {
      for (final c in r.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged([
      for (final r in rows)
        if (r.values.any((c) => c.text.trim().isNotEmpty)) {for (final e in r.entries) e.key: e.value.text.trim()},
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.hint != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: muted(context, widget.hint!)),
      Row(children: [
        for (final c in widget.columns)
          Expanded(flex: c.$3, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(c.$2, style: theme.textTheme.labelMedium),
          )),
        const SizedBox(width: 108),
      ]),
      const SizedBox(height: 4),
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in widget.columns)
              Expanded(
                flex: c.$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextField(
                    controller: rows[i][c.$1],
                    minLines: 1,
                    maxLines: widget.multilineKeys.contains(c.$1) ? 6 : 1,
                    onChanged: (_) => _emit(),
                  ),
                ),
              ),
            SizedBox(
              width: 108,
              child: Row(children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '위로',
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: i == 0 ? null : () => setState(() { final r = rows.removeAt(i); rows.insert(i - 1, r); _emit(); }),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '아래로',
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: i == rows.length - 1 ? null : () => setState(() { final r = rows.removeAt(i); rows.insert(i + 1, r); _emit(); }),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '삭제',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() { rows.removeAt(i); _emit(); }),
                ),
              ]),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('줄 추가'),
          onPressed: () => setState(() => rows.add(_ctl(const {}))),
        ),
      ),
    ]);
  }
}

/// 여러 개 고르기 (검색 가능). items: (id, 표시글)
Future<Set<int>?> pickMany(BuildContext context, String title, List<(int, String)> items, Set<int> selected) {
  final sel = {...selected};
  var filter = '';
  return showDialog<Set<int>>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final shown = items.where((x) => filter.isEmpty || x.$2.toLowerCase().contains(filter.toLowerCase())).toList();
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          height: 520,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '검색'),
              onChanged: (v) => setLocal(() => filter = v),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text('${sel.length}개 선택'),
              const Spacer(),
              TextButton(onPressed: () => setLocal(() => sel.addAll(shown.map((x) => x.$1))), child: const Text('보이는 것 모두 선택')),
              TextButton(onPressed: () => setLocal(() => sel.removeAll(shown.map((x) => x.$1))), child: const Text('선택 해제')),
            ]),
            Expanded(
              child: ListView(children: [
                for (final x in shown)
                  CheckboxListTile(
                    dense: true,
                    value: sel.contains(x.$1),
                    title: Text(x.$2),
                    onChanged: (v) => setLocal(() => v == true ? sel.add(x.$1) : sel.remove(x.$1)),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, sel), child: const Text('확인')),
        ],
      );
    }),
  );
}

/// 하나 고르기 (검색 가능, '없음' 가능)
Future<int?> pickOne(BuildContext context, String title, List<(int, String)> items, {int? current}) {
  var filter = '';
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final shown = items.where((x) => filter.isEmpty || x.$2.toLowerCase().contains(filter.toLowerCase())).toList();
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          height: 480,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '검색'),
              onChanged: (v) => setLocal(() => filter = v),
            ),
            Expanded(
              child: ListView(children: [
                ListTile(dense: true, title: const Text('(없음)'), onTap: () => Navigator.pop(ctx, -1)),
                for (final x in shown)
                  ListTile(
                    dense: true,
                    selected: x.$1 == current,
                    title: Text(x.$2),
                    onTap: () => Navigator.pop(ctx, x.$1),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소'))],
      );
    }),
  );
}

/// 드롭다운 (InputDecorator 안)
class Dropdown<T> extends StatelessWidget {
  const Dropdown({super.key, required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T? value;
  final List<(T?, String)> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final has = items.any((x) => x.$1 == value);
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: has ? value : null,
          isDense: true,
          isExpanded: true,
          items: [for (final x in items) DropdownMenuItem<T?>(value: x.$1, child: Text(x.$2))],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
