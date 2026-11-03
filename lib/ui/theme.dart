// Light (default) / Soft (grey light) / Dark / System, and the desktop's
// "modern" looks: Clean (white, indigo), Midnight (dark, violet, pill tabs) and
// Paper (warm, teal, the list in a rounded card). Their tokens are the
// desktop's (src/theme.cpp: cleanLook, midnightLook, paperLook); the accent
// also colours in-progress tasks there. The desktop's roomier rows are left
// out: rows stay 48 px here.

import 'package:flutter/material.dart';

enum AppTheme { light, soft, dark, clean, midnight, paper, system }

AppTheme themeFromString(String? s) => switch (s) {
  'soft' => AppTheme.soft,
  'dark' => AppTheme.dark,
  'clean' => AppTheme.clean,
  'midnight' => AppTheme.midnight,
  'paper' => AppTheme.paper,
  'system' => AppTheme.system,
  _ => AppTheme.light,
};

const themeLabels = {
  AppTheme.light: 'Light',
  AppTheme.soft: 'Soft',
  AppTheme.dark: 'Dark',
  AppTheme.clean: 'Clean',
  AppTheme.midnight: 'Midnight',
  AppTheme.paper: 'Paper',
  AppTheme.system: 'System (light / dark)',
};

ThemeData themeData(AppTheme t) => switch (t) {
  AppTheme.soft => softTheme(),
  AppTheme.dark => darkTheme(),
  AppTheme.clean => cleanTheme(),
  AppTheme.midnight => midnightTheme(),
  AppTheme.paper => paperTheme(),
  _ => lightTheme(),
};

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Colours that carry meaning in the task rows; derived from the palette so
/// they follow the theme (TaskColors::fromPalette on the desktop).
@immutable
class TaskColors extends ThemeExtension<TaskColors> {
  const TaskColors({
    required this.dark,
    required this.dim,
    required this.doing,
    required this.overdue,
    required this.today,
    required this.quick,
    required this.done,
    required this.band,
    required this.guide,
    required this.checkBorder,
    required this.pill,
    required this.pillText,
    required this.selection,
    required this.tag,
    this.radius = 4,
    this.card = false,
  });

  final bool dark;
  final Color dim, doing, overdue, today, quick, done, band, guide, checkBorder, pill, pillText, selection, tag;
  final double radius; // corners of inputs, buttons, pills
  final bool card; // the list sits in a rounded, bordered card (Paper)

  factory TaskColors.from(
    Color base,
    Color text,
    Color dim,
    Color selection,
    bool dark, {
    Color? doing,
    double radius = 4,
    bool card = false,
  }) => TaskColors(
    dark: dark,
    dim: dim,
    radius: radius,
    card: card,
    doing: doing ?? (dark ? const Color(0xff6caaf0) : const Color(0xff1f6fd0)),
    overdue: dark ? const Color(0xfff07070) : const Color(0xffc82a2a),
    today: dark ? const Color(0xffe8a840) : const Color(0xffb06a00),
    quick: dark ? const Color(0xff7cc87c) : const Color(0xff24803a),
    done: dark ? const Color(0xff4ca86a) : const Color(0xff2e9a57),
    band: _mix(base, text, dark ? 0.08 : 0.055),
    guide: _mix(base, text, 0.2),
    checkBorder: _mix(base, text, 0.45),
    pill: _mix(base, text, dark ? 0.22 : 0.12),
    pillText: _mix(base, text, dark ? 0.85 : 0.78),
    selection: selection,
    tag: dark ? const Color(0xffb69ae6) : const Color(0xff7446b0),
  );

  @override
  TaskColors copyWith() => this;

  @override
  TaskColors lerp(TaskColors? other, double t) => t < 0.5 || other == null ? this : other;
}

extension TaskColorsX on BuildContext {
  TaskColors get colors => Theme.of(this).extension<TaskColors>()!;
}

ThemeData _build({
  required Brightness brightness,
  required Color window,
  required Color base,
  required Color text,
  required Color dim,
  required Color accent,
  required Color selection,
  required Color button,
  Color? border, // the thin lines; default derived from base and text
  Color? input, // text field fill; default none
  double radius = 4,
  bool modern = false, // accent colours in-progress tasks, as on the desktop
  bool pills = false, // the nav bar marks the current tab with a pill
  bool card = false,
}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
    primary: accent,
    surface: base,
    onSurface: text,
    onSurfaceVariant: dim,
    surfaceContainerLowest: base,
    surfaceContainerLow: _mix(base, window, 0.5),
    surfaceContainer: window,
    surfaceContainerHigh: _mix(window, text, 0.04),
    surfaceContainerHighest: button,
    outline: _mix(base, text, 0.35),
    outlineVariant: _mix(base, text, 0.15),
    secondaryContainer: selection,
    onSecondaryContainer: text,
  );
  // Deliberately plain, not stock Material: square-ish corners, thin borders,
  // no tonal fills or tints, no ripples, no shadows.
  final line = border ?? _mix(base, text, 0.18);
  final corners = BorderRadius.circular(radius);
  final square = RoundedRectangleBorder(borderRadius: corners);
  final framed = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius + 2),
    side: BorderSide(color: line),
  );
  const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 9);
  final buttonText = const TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: card ? window : base,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    highlightColor: _mix(base, text, 0.06),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    appBarTheme: AppBarTheme(
      backgroundColor: window,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 52,
      shape: Border(bottom: BorderSide(color: line, width: 0.5)),
      titleTextStyle: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: window,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: pills ? selection : Colors.transparent,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius + 4)),
      height: 52,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(size: 20, color: s.contains(WidgetState.selected) ? accent : dim),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11.5,
          color: s.contains(WidgetState.selected) ? accent : dim,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
    bottomAppBarTheme: BottomAppBarThemeData(color: window, elevation: 0),
    dividerTheme: DividerThemeData(color: _mix(base, text, 0.12), space: 1, thickness: 1),
    chipTheme: ChipThemeData(
      side: BorderSide(color: line),
      shape: square,
      backgroundColor: base,
      selectedColor: selection,
      showCheckmark: false,
      labelStyle: TextStyle(color: text, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: input != null,
      fillColor: input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: corners,
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: corners,
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: corners,
        borderSide: BorderSide(color: accent, width: 1.2),
      ),
      hintStyle: TextStyle(color: dim),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: square, padding: pad, textStyle: buttonText, elevation: 0),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: square, padding: pad, textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: square,
        padding: pad,
        side: BorderSide(color: line),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: square,
        side: BorderSide(color: line),
        selectedBackgroundColor: selection,
        visualDensity: VisualDensity.compact,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius + 2)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: base,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: framed,
      titleTextStyle: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: base,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      showDragHandle: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius + 4)),
        side: BorderSide(color: line),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(color: base, surfaceTintColor: Colors.transparent, elevation: 2, shape: framed),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 6, horizontalTitleGap: 12),
    extensions: [
      TaskColors.from(base, text, dim, selection, dark, doing: modern ? accent : null, radius: radius, card: card),
    ],
  );
}

ThemeData lightTheme() => _build(
  brightness: Brightness.light,
  window: const Color(0xfff3f3f3),
  base: Colors.white,
  text: const Color(0xff1b1b1b),
  dim: const Color(0xff8a8a8a),
  accent: const Color(0xff1f6fd0),
  selection: const Color(0xffd6e4f7),
  button: const Color(0xffe6e6e6),
);

ThemeData softTheme() => _build(
  brightness: Brightness.light,
  window: const Color(0xffd5d8dc),
  base: const Color(0xffe2e5e8),
  text: const Color(0xff1f2328),
  dim: const Color(0xff838991),
  accent: const Color(0xff1f5fb0),
  selection: const Color(0xffbccde4),
  button: const Color(0xffcccfd5),
);

ThemeData darkTheme() => _build(
  brightness: Brightness.dark,
  window: const Color(0xff2b2b2b),
  base: const Color(0xff1e1e1e),
  text: const Color(0xffdcdcdc),
  dim: const Color(0xff808080),
  accent: const Color(0xff6caaf0),
  selection: const Color(0xff2d4a6a),
  button: const Color(0xff353535),
);

// The desktop's modern looks (src/theme.cpp). window = bars, base = the list.

ThemeData cleanTheme() => _build(
  brightness: Brightness.light,
  window: const Color(0xffffffff),
  base: const Color(0xffffffff),
  text: const Color(0xff1c1d21),
  dim: const Color(0xff8a8f98),
  accent: const Color(0xff5e6ad2),
  selection: const Color(0xffeceefc),
  button: const Color(0xfff1f1f4),
  border: const Color(0xffe8e8ec),
  radius: 6,
  modern: true,
);

ThemeData midnightTheme() => _build(
  brightness: Brightness.dark,
  window: const Color(0xff17181c),
  base: const Color(0xff17181c),
  text: const Color(0xffe4e5e9),
  dim: const Color(0xff7b808c),
  accent: const Color(0xff8b7cf6),
  selection: const Color(0xff2a2744),
  button: const Color(0xff1e1f25),
  border: const Color(0xff272930),
  input: const Color(0xff1e1f25),
  radius: 8,
  modern: true,
  pills: true,
);

ThemeData paperTheme() => _build(
  brightness: Brightness.light,
  window: const Color(0xfff3efe7),
  base: const Color(0xfffffdf9),
  text: const Color(0xff2b2620),
  dim: const Color(0xff8f8578),
  accent: const Color(0xff2f7d6d),
  selection: const Color(0xffe2efe9),
  button: const Color(0xffe8e2d6),
  border: const Color(0xffe2dacc),
  input: const Color(0xfffffdf9),
  radius: 10,
  modern: true,
  card: true,
);
