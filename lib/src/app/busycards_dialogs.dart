import 'package:flutter/material.dart';

import 'busycards_design.dart';
import 'busycards_shortcuts.dart';
import 'busycards_window_close.dart';

const _modalShortcuts = <ShortcutActivator, Intent>{
  BusyCardsShortcutActivators.keyboardShortcuts:
      DoNothingAndStopPropagationIntent(),
  BusyCardsShortcutActivators.settings: DoNothingAndStopPropagationIntent(),
  BusyCardsShortcutActivators.back: DoNothingAndStopPropagationIntent(),
};

/// Prevents application-level navigation shortcuts from escaping a modal
/// surface while preserving shortcuts owned by that surface's descendants.
///
/// Use this for modal UI that is not presented by [showBusyCardsModalDialog],
/// such as anchored popovers and in-page editor overlays.
class BusyCardsModalShortcutBoundary extends StatelessWidget {
  const BusyCardsModalShortcutBoundary({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(shortcuts: _modalShortcuts, child: child);
  }
}

Future<T?> showBusyCardsModalDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color? barrierColor,
  bool barrierDismissible = true,
}) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final result = await _showBusyCardsFlutterDialog<T>(
    context,
    builder: builder,
    barrierColor: barrierColor,
    barrierDismissible: barrierDismissible,
  );
  if (previousFocus?.context?.mounted == true &&
      previousFocus!.canRequestFocus) {
    previousFocus.requestFocus();
  }
  return result;
}

Future<T?> _showBusyCardsFlutterDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color? barrierColor,
  bool barrierDismissible = true,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final closeCoordinator = BusyCardsWindowCloseScope.maybeOf(context);
  final route = _BusyCardsDialogRoute<T>(
    context: context,
    builder: builder,
    themes: themes,
    closeCoordinator: closeCoordinator,
    fixedBarrierColor: barrierColor,
    initialBarrierColor: barrierColor ?? busyCardsModalBarrierColor(context),
    barrierDismissible: barrierDismissible,
  );
  final result = await navigator.push<T>(route);
  await route.completed;
  return result;
}

class _BusyCardsDialogRoute<T> extends DialogRoute<T> {
  _BusyCardsDialogRoute({
    required super.context,
    required WidgetBuilder builder,
    required CapturedThemes themes,
    required BusyCardsWindowCloseCoordinator? closeCoordinator,
    required Color? fixedBarrierColor,
    required Color initialBarrierColor,
    required super.barrierDismissible,
  }) : _fixedBarrierColor = fixedBarrierColor,
       _initialBarrierColor = initialBarrierColor,
       super(
         builder: (dialogContext) {
           final dialog = BusyCardsWindowCloseGuard(
             onCloseRequested: () => false,
             child: BusyCardsModalShortcutBoundary(
               child: builder(dialogContext),
             ),
           );
           return closeCoordinator == null
               ? dialog
               : BusyCardsWindowCloseScope(
                   coordinator: closeCoordinator,
                   child: dialog,
                 );
         },
         themes: themes,
         barrierColor: initialBarrierColor,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  final Color? _fixedBarrierColor;
  final Color _initialBarrierColor;

  /// Unlike [DialogRoute]'s constructor value, this getter is reevaluated
  /// when the Navigator's inherited theme changes.
  @override
  Color? get barrierColor {
    final fixedColor = _fixedBarrierColor;
    if (fixedColor != null) {
      return fixedColor;
    }
    final navigatorContext = navigator?.context;
    return navigatorContext == null
        ? _initialBarrierColor
        : busyCardsModalBarrierColor(navigatorContext);
  }
}

Future<T?> showBusyCardsModalEditorDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color? barrierColor,
  double maxWidth = BusyCardsSizes.compactDetailsWidth,
  double? maxHeight = 760,
}) async {
  return showBusyCardsModalDialog<T>(
    context,
    barrierColor: barrierColor,
    barrierDismissible: false,
    builder: (dialogContext) {
      return BusyCardsModalEditorSurface(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        insetPadding: const EdgeInsets.all(BusyCardsSpacing.lg),
        child: builder(dialogContext),
      );
    },
  );
}

Future<String?> showBusyCardsTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String actionLabel,
  String? initialValue,
  String? message,
  Color? barrierColor,
}) {
  return showBusyCardsModalDialog<String>(
    context,
    barrierColor: barrierColor,
    barrierDismissible: false,
    builder: (dialogContext) => BusyCardsPromptDialog(
      title: title,
      label: label,
      actionLabel: actionLabel,
      initialValue: initialValue,
      message: message,
    ),
  );
}

Future<bool> showBusyCardsConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  Color? barrierColor,
}) async {
  final confirmed = await showBusyCardsModalDialog<bool>(
    context,
    barrierColor: barrierColor,
    builder: (dialogContext) => BusyCardsConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
  return confirmed == true;
}
