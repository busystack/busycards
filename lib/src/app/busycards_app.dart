import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:system_theme/system_theme.dart';
import 'package:ubuntu_localizations/ubuntu_localizations.dart';

import '../../l10n/generated/app_localizations.dart';
import '../application/cards_runtime.dart';
import '../features/contacts/contacts_workspace.dart';
import '../platform/gtk_font_service.dart';
import '../platform/gtk_header_icon_service.dart';
import '../platform/gtk_animation_settings_service.dart';
import '../platform/native_style.dart';
import 'app_theme.dart';
import 'busycards_design.dart';
import 'busycards_surface_colors.dart';
import 'busycards_window_close.dart';
import 'linux/linux_window_host.dart';
import 'linux/linux_page_frame.dart';
import 'linux/linux_header_style.dart';

BusyCardsNativeSurfaceTheme busyCardsNativeSurfaceThemeFor(
  ThemeData theme, {
  required bool highContrast,
}) {
  final colors = theme.extension<BusyCardsSurfaceColors>()!;
  return BusyCardsNativeSurfaceTheme(
    highContrast: highContrast,
    windowBackgroundColor: colors.window,
    dialogBackgroundColor: colors.dialog,
    dialogOutlineColor: colors.dialogOutline,
    tooltipBackgroundColor: BusyCardsTooltipStyle.background,
    tooltipForegroundColor: BusyCardsTooltipStyle.foreground,
    tooltipBorderColor: BusyCardsTooltipStyle.border,
    tooltipRadius: BusyCardsRadius.tooltip,
    tooltipFontSize: theme.tooltipTheme.textStyle?.fontSize ?? 14,
    tooltipHorizontalPadding: BusyCardsSpacing.tooltipHorizontal,
    tooltipVerticalPadding: BusyCardsSpacing.tooltipVertical,
    tooltipMinimumHeight: BusyCardsSizes.tooltipMinHeight,
  );
}

class LinuxBusyCardsApp extends ConsumerStatefulWidget {
  const LinuxBusyCardsApp({super.key, required this.openRuntime});
  final Future<CardsRuntime> Function() openRuntime;
  @override
  ConsumerState<LinuxBusyCardsApp> createState() => _LinuxBusyCardsAppState();
}

class _LinuxBusyCardsAppState extends ConsumerState<LinuxBusyCardsApp> {
  final _close = BusyCardsWindowCloseCoordinator();
  late Future<CardsRuntime> _runtime = _open();
  CardsRuntime? _opened;
  ThemeMode _themeMode = ThemeMode.system;
  BusyCardsNativeSurfaceTheme? _surface;
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          backgroundColor: BusyCardsSurfaceColors.of(context).window,
          body: FutureBuilder<CardsRuntime>(
            future: _runtime,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return ContactsWorkspace(
                  runtime: snapshot.data!,
                  themeMode: _themeMode,
                  onTheme: _setTheme,
                );
              }
              return LinuxPageFrame(
                header: const BusyCardsLinuxHeaderLayout(
                  leading: SizedBox.shrink(),
                  title: BusyCardsLinuxHeaderTitle('BusyCards'),
                  trailing: SizedBox.shrink(),
                ),
                body: BusyCardsEmptyState(
                  icon: Icons.contacts_outlined,
                  title: snapshot.hasError
                      ? 'Unlock BusyCards storage'
                      : 'Opening BusyCards',
                  message: snapshot.hasError
                      ? 'Unlock the system keyring, then retry. Your encrypted contacts stay on this device.'
                      : 'Preparing your private contact directory.',
                  actions: snapshot.hasError
                      ? [
                          BusyCardsPushButton.suggested(
                            onPressed: () {
                              setState(() {
                                _runtime = _open();
                              });
                            },
                            child: const Text('Retry'),
                          ),
                        ]
                      : [],
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
  Future<CardsRuntime> _open() async {
    final runtime = await widget.openRuntime();
    _opened = runtime;
    final preference = await runtime.secrets.read('theme-mode');
    if (mounted)
      setState(() {
        _themeMode =
            ThemeMode.values.where((e) => e.name == preference).firstOrNull ??
            ThemeMode.system;
      });
    return runtime;
  }

  void _setTheme(ThemeMode mode) {
    setState(() => _themeMode = mode);
    unawaited(_opened?.secrets.write('theme-mode', mode.name));
    unawaited(
      const GtkThemeService().setPreferDark(
        mode == ThemeMode.system ? null : mode == ThemeMode.dark,
      ),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    unawaited(_opened?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final font = ref.watch(gtkFontSettingsProvider).value;
    final colors = ref.watch(gtkThemeColorsProvider).value;
    final animations = ref.watch(gtkAnimationsEnabledProvider).value ?? true;
    return SystemThemeBuilder(
      builder: (context, systemColor) {
        ThemeData theme(Brightness brightness, [bool highContrast = false]) =>
            buildBusyCardsTheme(
              brightness: brightness,
              accentColor: colors?.accent ?? systemColor.accent,
              gtkFontFamily: font?.family,
              gtkFontSize: font?.size,
              gtkThemeColors: colors,
              highContrast: highContrast,
            );
        return MaterialApp.router(
          title: 'BusyCards',
          debugShowCheckedModeBanner: false,
          theme: theme(Brightness.light),
          darkTheme: theme(Brightness.dark),
          highContrastTheme: theme(Brightness.light, true),
          highContrastDarkTheme: theme(Brightness.dark, true),
          themeMode: _themeMode,
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            ...GlobalUbuntuLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: _router,
          builder: (context, child) {
            final surface = busyCardsNativeSurfaceThemeFor(
              Theme.of(context),
              highContrast: MediaQuery.highContrastOf(context),
            );
            if (_surface != surface) {
              _surface = surface;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted)
                  unawaited(
                    const NativeSurfaceStyleService().setTheme(surface),
                  );
              });
            }
            return GtkHeaderIconScope(
              service: ref.watch(gtkHeaderIconServiceProvider),
              child: LinuxApplicationMediaQuery(
                alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                  context,
                ),
                gtkAnimationsEnabled: animations,
                child: LinuxWindowHost(
                  closeCoordinator: _close,
                  child: ColoredBox(
                    color: BusyCardsSurfaceColors.of(context).window,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Same display, accessibility and reduced-motion policy as BusyMax.
class LinuxApplicationMediaQuery extends StatelessWidget {
  const LinuxApplicationMediaQuery({
    super.key,
    required this.alwaysUse24HourFormat,
    required this.gtkAnimationsEnabled,
    required this.child,
  });
  final bool alwaysUse24HourFormat, gtkAnimationsEnabled;
  final Widget child;
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      alwaysUse24HourFormat: alwaysUse24HourFormat,
      disableAnimations:
          MediaQuery.disableAnimationsOf(context) || !gtkAnimationsEnabled,
    ),
    child: child,
  );
}
