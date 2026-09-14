import 'package:flutter_test/flutter_test.dart';

import 'package:voxdesk/core/formatters.dart';

void main() {
  group('formatClock', () {
    test('基本格式', () {
      expect(formatClock(0), '00:00:00');
      expect(formatClock(5), '00:00:05');
      expect(formatClock(80), '00:01:20');
      expect(formatClock(3661), '01:01:01');
    });
    test('小数向下取整', () {
      expect(formatClock(4.9), '00:00:04');
    });
    test('负数钳制为 0', () {
      expect(formatClock(-3), '00:00:00');
    });
  });

  group('formatDuration', () {
    test('无小时', () {
      expect(formatDuration(0), '0:00');
      expect(formatDuration(58 * 60 + 3), '58:03');
    });
    test('含小时', () {
      expect(formatDuration(3600 + 2 * 60 + 33), '1:02:33');
    });
  });

  group('formatDateTime', () {
    test('格式 yyyy-MM-dd HH:mm:ss', () {
      expect(
        formatDateTime(DateTime(2024, 1, 16, 10, 24, 17)),
        '2024-01-16 10:24:17',
      );
    });
  });

  group('formatFileSize', () {
    test('MB', () {
      expect(formatFileSize(325.4 * 1024 * 1024), '325.4 MB');
    });
    test('GB', () {
      expect(formatFileSize(1.5 * 1024 * 1024 * 1024), '1.5 GB');
    });
    test('KB', () {
      expect(formatFileSize(846 * 1024), '846 KB');
    });
  });

  group('formatCount', () {
    test('千分位', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(12548), '12,548');
      expect(formatCount(1234567), '1,234,567');
      expect(formatCount(-12548), '-12,548');
    });
  });
}
