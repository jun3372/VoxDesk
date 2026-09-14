import 'package:flutter/material.dart';

/// 设计图中的品牌色板（暖白底 + 品牌红）。
abstract final class AppColors {
  static const background = Color(0xFFF8F0EC);
  static const card = Color(0xFFFFFFFF);
  static const cardWarm = Color(0xFFFFFBFA);

  static const primary = Color(0xFFE5474D);
  static const primaryLight = Color(0xFFE85A55);
  static const primaryDark = Color(0xFFD93A44);
  static const primarySoft = Color(0xFFFBEAE6);
  static const primarySoftAlt = Color(0xFFFDF1EE);
  static const primaryBorder = Color(0xFFF0B9B0);

  static const border = Color(0xFFF0E0DC);
  static const textPrimary = Color(0xFF2B2B33);
  static const textSecondary = Color(0xFF8A8A93);

  static const success = Color(0xFF34A853);
  static const successSoft = Color(0xFFE6F6EC);

  static const primaryGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryLight, primaryDark],
  );

  /// 历史列表按扩展名着色的文件类型图标。
  static Color fileIcon(String ext) => switch (ext.toLowerCase()) {
    'txt' => const Color(0xFFE5474D),
    'wav' => const Color(0xFFD6409F),
    'mp3' => const Color(0xFF0EA5B7),
    'm4a' => const Color(0xFFF08C2E),
    'flac' => const Color(0xFF3B82F6),
    'ogg' => const Color(0xFF34A853),
    _ => textSecondary,
  };
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.card,
    ),
    scaffoldBackgroundColor: AppColors.background,
    // 默认字体用内嵌的 MiSans（pubspec.yaml fonts）：Linux 目标机（云桌面/
    // 精简 UOS）可能没有任何系统中文字体，不指定会全部显示为豆腐块。
    fontFamily: 'MiSans',
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
      // 个别字形 MiSans 覆盖不到时也优先回退内嵌字体，不落系统字体
      fontFamilyFallback: const ['MiSans'],
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
      ),
      // Tooltip 会整体替换默认文本样式而不是合并 DefaultTextStyle，
      // 因此必须自带 fontFamily，否则 Linux 上中文变豆腐块。
      textStyle: base.textTheme.bodySmall?.copyWith(color: Colors.white),
    ),
  );
}
