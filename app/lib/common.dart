import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'settings.dart';
import 'state.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String dateStr(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
String todayStr() => dateStr(DateTime.now());

/// 2027-01-01 → 2027. 1. 1.
String fmtDate(String? d) {
  if (d == null || d.length < 10) return '';
  final p = d.substring(0, 10).split('-');
  return '${p[0]}. ${int.parse(p[1])}. ${int.parse(p[2])}.';
}

/// ISO 시각 → 2026. 10. 27. 14:05 (현지 시간)
String fmtDateTime(String? iso) {
  if (iso == null) return '';
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  final l = t.toLocal();
  return '${l.year}. ${l.month}. ${l.day}. ${_two(l.hour)}:${_two(l.minute)}';
}

/// 기한까지 남은 날: D-3, D-day, D+2 (지남)
String dday(String? d) {
  final t = DateTime.tryParse(d ?? '');
  if (t == null) return '';
  final now = DateTime.now();
  final diff = DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (diff == 0) return 'D-day';
  return diff > 0 ? 'D-$diff' : 'D+${-diff}';
}

int? daysLeft(String? d) {
  final t = DateTime.tryParse(d ?? '');
  if (t == null) return null;
  final now = DateTime.now();
  return DateTime(t.year, t.month, t.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

String humanSize(num n) {
  if (n < 1024) return '${n.toInt()}B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)}KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)}MB';
}

String errorText(Object e) => e is ApiException ? e.message : e.toString();

void showError(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(errorText(e)),
    backgroundColor: Theme.of(context).colorScheme.error,
    duration: const Duration(seconds: 6),
  ));
}

void showInfo(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirmDialog(BuildContext context, String title, String message,
    {String ok = '확인', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 420, child: Text(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

/// 한 줄 입력 대화상자
Future<String?> promptText(BuildContext context, String title,
    {String label = '', String initial = '', int maxLines = 1, bool required = false}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: TextField(
          controller: c,
          autofocus: true,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 2 : 1,
          decoration: InputDecoration(labelText: label),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        FilledButton(
          onPressed: () {
            if (required && c.text.trim().isEmpty) return;
            Navigator.pop(ctx, c.text.trim());
          },
          child: const Text('확인'),
        ),
      ],
    ),
  );
  c.dispose();
  return r;
}

/// 받은 파일을 사용자가 고른 위치에 저장
Future<void> saveBytes(BuildContext context, String suggestedName, Uint8List bytes) async {
  final ext = suggestedName.contains('.') ? suggestedName.split('.').last : '';
  final loc = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [if (ext.isNotEmpty) XTypeGroup(label: ext.toUpperCase(), extensions: [ext])],
  );
  if (loc == null) return;
  var path = loc.path;
  if (ext.isNotEmpty && !path.toLowerCase().endsWith('.$ext')) path = '$path.$ext';
  await File(path).writeAsBytes(bytes);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('저장했습니다: $path'),
      action: SnackBarAction(label: '폴더 열기', onPressed: () => openFolderOf(path)),
    ));
  }
}

/// 서버에서 파일을 받아 저장 (GET)
Future<void> downloadTo(BuildContext context, String apiPath, String suggestedName, {Map<String, String?>? query}) async {
  try {
    final bytes = await api.download(apiPath, query: query);
    if (!context.mounted) return;
    await saveBytes(context, suggestedName, bytes);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// 서버 파일을 임시 폴더에 받아 기본 프로그램(엑셀 등)으로 연다. 원본은 그대로.
Future<void> openWithDefaultApp(BuildContext context, String apiPath, String filename) async {
  try {
    final bytes = await api.download(apiPath);
    final dir = Directory('${Directory.systemTemp.path}${sep}WorkGuideline');
    await dir.create(recursive: true);
    final f = File('${dir.path}$sep${filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}');
    await f.writeAsBytes(bytes);
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', f.path], runInShell: false);
    } else {
      await Process.run('xdg-open', [f.path]);
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

void openFolderOf(String path) {
  if (Platform.isWindows) Process.run('explorer', ['/select,', path]);
}

/// 파일 이름에서 확장자
String extOf(String name) => name.contains('.') ? '.${name.split('.').last}' : '';

/// 상태 표시 배지
class Badge2 extends StatelessWidget {
  const Badge2(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Color dueColor(String? due, String? status) {
  if (status == '완료' || status == '해당없음') return const Color(0xFF2E7D32);
  final d = daysLeft(due);
  if (d == null) return Colors.grey;
  if (d < 0) return const Color(0xFFC62828);
  if (d <= 7) return const Color(0xFFEF6C00);
  return const Color(0xFF1565C0);
}

/// 날짜 선택 필드 (값: YYYY-MM-DD)
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.enabled = true});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final v = (value ?? '').isEmpty ? null : value;
    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              final init = DateTime.tryParse(v ?? '') ?? DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: init,
                firstDate: DateTime(1980),
                lastDate: DateTime(2100),
              );
              if (d != null) onChanged(dateStr(d));
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: v != null && enabled
              ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => onChanged(null))
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(v == null ? '선택' : fmtDate(v)),
      ),
    );
  }
}

/// 제목 + 내용 묶음 (상세 화면용)
class Section extends StatelessWidget {
  const Section(this.title, this.children, {super.key, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
        const Divider(height: 10),
        ...children,
      ]),
    );
  }
}

/// 비어 있을 때 회색 안내
Widget muted(BuildContext context, String text) =>
    Text(text, style: TextStyle(color: Theme.of(context).colorScheme.outline));

/// 단순 표 (머리줄 + 줄들). 글자가 길면 줄바꿈
class SimpleTable extends StatelessWidget {
  const SimpleTable({super.key, required this.headers, required this.rows, this.flex});
  final List<String> headers;
  final List<List<Widget>> rows;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = BorderSide(color: theme.colorScheme.outlineVariant);
    final widths = <int, TableColumnWidth>{
      for (var i = 0; i < headers.length; i++) i: FlexColumnWidth((flex?[i] ?? 1).toDouble()),
    };
    Widget cell(Widget w, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: head ? DefaultTextStyle.merge(style: const TextStyle(fontWeight: FontWeight.bold), child: w) : w,
        );
    return Table(
      columnWidths: widths,
      border: TableBorder(top: border, bottom: border, horizontalInside: border, left: border, right: border, verticalInside: border),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh),
          children: [for (final h in headers) cell(Text(h), head: true)],
        ),
        for (final r in rows) TableRow(children: [for (final c in r) cell(c)]),
      ],
    );
  }
}

/// 링크처럼 보이는 글자
class LinkText extends StatelessWidget {
  const LinkText(this.text, this.onTap, {super.key});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(text,
          style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
    );
  }
}

String txt(dynamic v) => v == null ? '' : '$v';
List<Map<String, dynamic>> maps(dynamic v) => [for (final x in (v as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
