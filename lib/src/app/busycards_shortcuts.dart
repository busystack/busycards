import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class BusyCardsShortcutActivators {
  static const back = SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true);
  static const keyboardShortcuts = SingleActivator(
    LogicalKeyboardKey.keyK,
    control: true,
    alt: true,
  );
  static const settings = SingleActivator(
    LogicalKeyboardKey.keyS,
    control: true,
    alt: true,
  );
  static const search = SingleActivator(LogicalKeyboardKey.keyF, control: true);
  static const sidebar = SingleActivator(LogicalKeyboardKey.f9);
  static const dismiss = SingleActivator(LogicalKeyboardKey.escape);
}
