import 'package:flutter/material.dart';

/// 主题色预设
class ColorPreset {
  final String name;
  final Color color;
  const ColorPreset(this.name, this.color);
}

const List<ColorPreset> kColorPresets = <ColorPreset>[
  ColorPreset('靛蓝', Color(0xFF4C6CFF)),
  ColorPreset('紫罗兰', Color(0xFFA855F7)),
  ColorPreset('青碧', Color(0xFF06B6D4)),
  ColorPreset('翡翠', Color(0xFF10B981)),
  ColorPreset('落日', Color(0xFFF97316)),
  ColorPreset('玫红', Color(0xFFF43F5E)),
];

const Color kDefaultSeed = Color(0xFF4C6CFF);

/// 解析设置里的颜色值：支持 #RRGGBB / #AARRGGBB / 预设名
Color parseSeedColor(String? raw) {
  if (raw == null || raw.isEmpty) return kDefaultSeed;
  final v = raw.trim();
  if (v.startsWith('#')) {
    var hex = v.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed != null) return Color(parsed);
  }
  for (final p in kColorPresets) {
    if (p.name == v) return p.color;
  }
  return kDefaultSeed;
}

String colorToHex(Color c) {
  final argb = c.toARGB32();
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 消息主题色（[i] 信息 / [s] 成功 / [w] 警告 / [f] 失败）
Color themeAccent(String theme, ColorScheme scheme) {
  switch (theme) {
    case 'i':
      return const Color(0xFF3B82F6);
    case 's':
      return const Color(0xFF10B981);
    case 'w':
      return const Color(0xFFF59E0B);
    case 'f':
      return const Color(0xFFEF4444);
    default:
      return scheme.primary;
  }
}

IconData themeIcon(String theme) {
  switch (theme) {
    case 'i':
      return Icons.info_rounded;
    case 's':
      return Icons.check_circle_rounded;
    case 'w':
      return Icons.warning_rounded;
    case 'f':
      return Icons.error_rounded;
    default:
      return Icons.notifications_rounded;
  }
}

String themeLabel(String theme) {
  switch (theme) {
    case 'i':
      return '信息';
    case 's':
      return '成功';
    case 'w':
      return '警告';
    case 'f':
      return '失败';
    default:
      return '普通';
  }
}

ThemeData buildAppTheme(Color seed, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  ).copyWith(
    surface: isDark ? const Color(0xFF0F1115) : const Color(0xFFF6F7FB),
    surfaceContainerLowest: isDark ? const Color(0xFF171A21) : Colors.white,
    surfaceContainerLow: isDark ? const Color(0xFF1C2029) : const Color(0xFFF0F2F8),
    surfaceContainerHigh: isDark ? const Color(0xFF232833) : const Color(0xFFE9ECF4),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: isDark ? const Color(0xFFE8EAF0) : const Color(0xFF16181D),
      displayColor: isDark ? const Color(0xFFE8EAF0) : const Color(0xFF16181D),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: isDark ? const Color(0xFFE8EAF0) : const Color(0xFF16181D),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.55 : 0.7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        fontSize: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.6), width: 1.4),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF12151B) : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? const Color(0xFF262B36) : const Color(0xFFE6E9F2),
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF1A1E26) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF1A1E26) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: isDark ? const Color(0xFFE8EAF0) : const Color(0xFF16181D),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFF2A2F3A) : const Color(0xFF24272E),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return isDark ? const Color(0xFF9AA3B2) : const Color(0xFFB8BECB);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.primary;
        return isDark ? const Color(0xFF333A47) : const Color(0xFFDDE2EC);
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
      secondaryLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
  );
}
