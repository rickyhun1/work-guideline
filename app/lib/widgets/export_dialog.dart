import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';

/// 체크한 항목을 zip 하나로 내보내기
Future<void> showExportDialog(
  BuildContext context, {
  Set<int> documentIds = const {},
  Set<int> formIds = const {},
  Set<int> lawIds = const {},
  Set<int> projectIds = const {},
  String defaultName = '업무표준 내보내기',
}) async {
  final name = TextEditingController(text: '$defaultName ${todayStr()}');
  var includeForms = true;
  var includeAttachments = false;
  var includeProjectFiles = true;
  var busy = false;
  final parts = [
    if (documentIds.isNotEmpty) '문서 ${documentIds.length}개',
    if (formIds.isNotEmpty) '양식 ${formIds.length}개',
    if (lawIds.isNotEmpty) '법령 ${lawIds.length}건',
    if (projectIds.isNotEmpty) '프로젝트 ${projectIds.length}건',
  ];
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      Future<void> run() async {
        setLocal(() => busy = true);
        try {
          final bytes = await api.postDownload('/export/package', {
            'documentIds': documentIds.toList(),
            'formIds': formIds.toList(),
            'lawIds': lawIds.toList(),
            'projectIds': projectIds.toList(),
            'includeForms': includeForms,
            'includeAttachments': includeAttachments,
            'includeProjectFiles': includeProjectFiles,
            'name': name.text.trim(),
          });
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          if (context.mounted) await saveBytes(context, '${name.text.trim().isEmpty ? '내보내기' : name.text.trim()}.zip', bytes);
        } catch (e) {
          if (ctx.mounted) showError(ctx, e);
          setLocal(() => busy = false);
        }
      }

      return AlertDialog(
        title: const Text('선택 항목 묶어서 내보내기 (zip)'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(parts.join(', '), style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: '파일 이름')),
            const SizedBox(height: 8),
            if (documentIds.isNotEmpty)
              CheckboxListTile(
                value: includeForms,
                onChanged: (v) => setLocal(() => includeForms = v ?? true),
                title: const Text('문서마다 관련 양식 파일 포함'),
                subtitle: const Text('각 문서 폴더 안 "양식" 폴더에 최신 파일을 현재 번호로'),
              ),
            if (documentIds.isNotEmpty || lawIds.isNotEmpty)
              CheckboxListTile(
                value: includeAttachments,
                onChanged: (v) => setLocal(() => includeAttachments = v ?? false),
                title: const Text('첨부 파일 포함 (원본 문서, 참고자료 등)'),
              ),
            if (projectIds.isNotEmpty)
              CheckboxListTile(
                value: includeProjectFiles,
                onChanged: (v) => setLocal(() => includeProjectFiles = v ?? true),
                title: const Text('프로젝트 제출서류·공통자료 포함'),
              ),
            const SizedBox(height: 8),
            muted(ctx, '문서는 현재 입력된 내용과 번호 체계로 엑셀 파일을 새로 만들고, 목록표를 함께 넣습니다.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton.icon(
            onPressed: busy ? null : run,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.archive_outlined),
            label: const Text('내보내기'),
          ),
        ],
      );
    }),
  );
  name.dispose();
}
