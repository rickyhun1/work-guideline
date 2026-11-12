import 'package:flutter_test/flutter_test.dart';
import 'package:work_guideline/common.dart';

void main() {
  test('날짜 표시', () {
    expect(fmtDate('2027-03-05'), '2027. 3. 5.');
    expect(fmtDate(null), '');
  });

  test('D-day', () {
    final today = todayStr();
    expect(dday(today), 'D-day');
    expect(dday(''), '');
    expect(daysLeft('2000-01-01')! < 0, isTrue);
  });

  test('파일 크기', () {
    expect(humanSize(500), '500B');
    expect(humanSize(2048), '2KB');
  });
}
