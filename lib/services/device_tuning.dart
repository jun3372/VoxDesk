import 'dart:io';

/// 引擎并行参数（按设备算力自动调节，见 [probeDeviceTuning]）。
class DeviceTuning {
  const DeviceTuning({
    required this.asrWorkers,
    required this.asrThreads,
    required this.diarThreads,
  });

  /// ASR 并行 worker 数（每个 worker 独立加载一份约 1.2GB 的模型）。
  final int asrWorkers;

  /// 每个 ASR worker 的解码线程数。
  final int asrThreads;

  /// 说话人分离的线程数。
  final int diarThreads;
}

/// 探测设备核数与内存，决定 ASR 并行度与各引擎线程数。
///
/// 实测基准（tool/bench_asr.dart，8 核 16GB Apple Silicon，12s 音频）：
/// 单 recognizer 线程数 2/4/6/8 的解码耗时为 4.29/2.67/2.96/3.00s ——
/// 4 线程（性能核数）最优，更多线程受内存带宽与能效核拖累反而变慢；
/// 而在 8 核机上再加第 2 个 worker（4+4 线程并发解码）吞吐仅 +15%，
/// 内存却翻倍（每 worker 独立加载一份模型）。因此线程数按 4 封顶；
/// 仅当核数远超 4（能再容下一整个 worker 的 4 线程）且内存充裕时才
/// 启用第 2 个 worker。内存读不到时只按核数判断。
Future<DeviceTuning> probeDeviceTuning() async {
  final cores = Platform.numberOfProcessors;
  final ramGb = await _totalMemoryGb();
  final workers =
      cores >= 12 && (ramGb == null || ramGb >= 16) ? 2 : 1;
  return DeviceTuning(
    asrWorkers: workers,
    asrThreads: _clampInt(cores ~/ workers, 2, 4),
    // 分离与 ASR 并行跑，只分给一半核数，避免过度争抢
    diarThreads: _clampInt(cores ~/ 2, 2, 4),
  );
}

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// 读取物理内存总量（GB），读不到返回 null（调用方按核数保守估计）。
Future<double?> _totalMemoryGb() async {
  try {
    if (Platform.isMacOS) {
      final r = await Process.run('sysctl', [
        '-n',
        'hw.memsize',
      ]).timeout(const Duration(seconds: 3));
      final bytes = int.tryParse('${r.stdout}'.trim());
      if (bytes != null) return bytes / (1 << 30);
    } else if (Platform.isLinux) {
      for (final line in await File('/proc/meminfo').readAsLines()) {
        if (line.startsWith('MemTotal:')) {
          final kb = int.tryParse(line.split(RegExp(r'\s+'))[1]);
          if (kb != null) return kb / (1 << 20);
        }
      }
    } else if (Platform.isWindows) {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
      ]).timeout(const Duration(seconds: 5));
      final bytes = int.tryParse('${r.stdout}'.trim());
      if (bytes != null) return bytes / (1 << 30);
    }
  } catch (_) {}
  return null;
}
