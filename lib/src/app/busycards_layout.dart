import 'package:yaru/yaru.dart';

import 'busycards_design.dart';

abstract final class BusyCardsLayoutRules {
  static const double sidebarBreakpoint =
      kYaruMasterDetailBreakpoint + BusyCardsSizes.sidebarWidth / 4;
  static const double detailsBreakpoint = kYaruMasterDetailBreakpoint * 2;
  static const double taskPageMinWidth =
      kYaruMasterDetailBreakpoint - BusyCardsSizes.sidebarWidth / 2;
  static const double settingsSidebarBreakpoint =
      BusyCardsSizes.sidebarWidth + 520;

  static bool showSidebar(double width) => width >= sidebarBreakpoint;

  static bool showPersistentDetails(double width) => width >= detailsBreakpoint;

  static bool showSettingsSidebar(double width) =>
      width >= settingsSidebarBreakpoint;
}
