/// 时间与文本格式化工具。
library;

/// 秒数 → `HH:MM:SS`（转写时间戳样式，如 `00:01:20`）。
String formatClock(num seconds) {
  final s = seconds.floor().clamp(0, 359999);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return '${_two(h)}:${_two(m)}:${_two(sec)}';
}

/// 秒数 → 紧凑时长（`58:03` 或 `1:02:33`）。
String formatDuration(num seconds) {
  final s = seconds.floor().clamp(0, 359999);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return '$h:${_two(m)}:${_two(sec)}';
  return '$m:${_two(sec)}';
}

/// DateTime → `2024-01-16 10:24:17`。
String formatDateTime(DateTime dt) {
  final m = _two(dt.month);
  final d = _two(dt.day);
  final hh = _two(dt.hour);
  final mm = _two(dt.minute);
  final ss = _two(dt.second);
  return '${dt.year}-$m-$d $hh:$mm:$ss';
}

/// 字节数 → `325.4 MB` / `1.2 GB` / `846 KB`。
String formatFileSize(num bytes) {
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '${bytes.round()} B';
}

/// 整数千分位 → `12,548`。
String formatCount(int n) {
  final sign = n < 0 ? '-' : '';
  final digits = n.abs().toString();
  final buf = StringBuffer(sign);
  for (var i = 0; i < digits.length; i++) {
    buf.write(digits[i]);
    final remain = digits.length - i - 1;
    if (remain > 0 && remain % 3 == 0) buf.write(',');
  }
  return buf.toString();
}

String _two(int n) => n.toString().padLeft(2, '0');
