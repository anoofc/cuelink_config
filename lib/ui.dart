import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class CueSpace {
  static const screen = EdgeInsets.fromLTRB(20, 12, 20, 24);
  static const card = EdgeInsets.all(16);
  static const gap = 12.0;
  static const section = 24.0;
  static const radius = 16.0;
}

/// Consistent control spacing without doubling explicit section gaps.
class ControlColumn extends StatelessWidget {
  const ControlColumn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });
  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  @override
  Widget build(BuildContext context) {
    final visible = children
        .where(
          (child) =>
              !(child is SizedBox &&
                  child.width == 0 &&
                  child.height == 0 &&
                  child.child == null),
        )
        .toList();
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0 && visible[i] is! SizedBox && visible[i - 1] is! SizedBox)
            const SizedBox(height: CueSpace.gap),
          visible[i],
        ],
      ],
    );
  }
}

class OptionalHelp extends StatelessWidget {
  const OptionalHelp(this.title, this.text, {super.key});
  final String title, text;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    title: Text(title, style: Theme.of(context).textTheme.bodySmall),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

ThemeData cueLinkTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff53e0ec),
    brightness: Brightness.dark,
    primary: const Color(0xff53e0ec),
    surface: const Color(0xff1a2128),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: const Color(0xff101418),
    textTheme: TextTheme(
      headlineLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      headlineSmall: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
      titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
      titleMedium: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      bodyLarge: const TextStyle(fontSize: 16),
      bodyMedium: const TextStyle(fontSize: 16),
      bodySmall: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CueSpace.radius),
      ),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: CueSpace.card),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: CueSpace.card,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xff101418),
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}

AppBar cueAppBar(
  BuildContext context,
  String title, {
  Widget? titleWidget,
  List<Widget>? actions,
}) => AppBar(
  toolbarHeight: math.max(
    56,
    MediaQuery.textScalerOf(context).scale(22) * 2 + 8,
  ),
  title: titleWidget ?? Text(title, maxLines: 2),
  actions: actions,
);

/// Stack the label above its switch when larger text needs the full width.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });
  final Widget title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 360 &&
          MediaQuery.textScalerOf(context).scale(16) > 24) {
        return InkWell(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                Align(
                  alignment: Alignment.centerRight,
                  child: Switch(value: value, onChanged: onChanged),
                ),
              ],
            ),
          ),
        );
      }
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: title,
        value: value,
        onChanged: onChanged,
      );
    },
  );
}
