import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'pages/home_page.dart';

class VoxDesk extends StatelessWidget {
  const VoxDesk({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '离线语音工作台',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomePage(),
      scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: true),
      // 全局字体兜底：theme.fontFamily 只覆盖 Material 组件树，而
      // Navigator/Overlay 等无 Material 祖先的上下文里环境默认样式是
      // 裸样式（无 fontFamily），落回系统字体——目标 Linux 机没有中
      // 文字体时即豆腐块。此处对整个组件树强制 MiSans：fontFamily
      // 兜住默认解析，fontFamilyFallback 兜住个别组件显式指定了仅
      // 覆盖西文的字体而缺中文字形的场景。
      builder: (context, child) {
        return DefaultTextStyle(
          style: DefaultTextStyle.of(context).style.copyWith(
            fontFamily: 'MiSans',
            fontFamilyFallback: const ['MiSans'],
          ),
          child: child!,
        );
      },
    );
  }
}
