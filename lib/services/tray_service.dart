import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart' as tray;

/// System tray (Windows) / menu bar (macOS) icon with a small menu:
/// Show SK EQ · Equalizer on/off · Check for Updates · Quit.
///
/// Uses tray_manager's native API. It is prefixed because its `Image`,
/// `Menu` and `MenuItem` names clash with Flutter's.
class TrayService {
  tray.TrayIcon? _icon;
  tray.Menu? _menu;
  tray.MenuItem? _eqItem;

  /// True once the icon is showing. If tray creation fails, the window's
  /// close button should quit instead of hiding to an invisible tray.
  bool get isAvailable => _icon != null;

  /// Creates the icon. Returns false (and logs) if the platform refused.
  bool init({
    required bool eqEnabled,
    required VoidCallback onShow,
    required ValueChanged<bool> onEqChanged,
    required VoidCallback onCheckUpdates,
    required VoidCallback onQuit,
  }) {
    try {
      final icon = tray.TrayIcon.create();
      final menu = tray.Menu.create();
      if (icon == null || menu == null) return false;

      if (Platform.isMacOS) {
        // Monochrome template image: macOS tints it for light/dark menu bars.
        icon.icon =
            tray.ImageAsset.fromAsset('assets/tray/tray_icon_template.png');
        icon.isIconTemplate = true;
      } else {
        icon.icon = tray.ImageAsset.fromAsset('assets/tray/tray_icon.ico');
      }
      icon.setTooltip('SK EQ');

      final show = _item('Show SK EQ', tray.MenuItemType.normal, onShow);
      _eqItem = _item('Equalizer', tray.MenuItemType.checkbox, () {
        // A click does not toggle a native checkbox by itself.
        onEqChanged(_eqItem?.state != tray.MenuItemState.checked);
      });
      setEqEnabled(eqEnabled);
      final updates =
          _item('Check for Updates…', tray.MenuItemType.normal, onCheckUpdates);
      final quit = _item('Quit SK EQ', tray.MenuItemType.normal, onQuit);

      menu
        ..addItem(show)
        ..addItem(_eqItem)
        ..addSeparator()
        ..addItem(updates)
        ..addSeparator()
        ..addItem(quit);

      icon
        ..setContextMenu(menu)
        // Right-click opens the menu; left-click brings the window back.
        ..setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked)
        ..addListener((event) {
          if (event is tray.TrayIconClickedEvent ||
              event is tray.TrayIconDoubleClickedEvent) {
            onShow();
          }
        })
        ..setVisible(true);

      // Keep references alive: a garbage-collected TrayIcon removes itself.
      _icon = icon;
      _menu = menu;
      return true;
    } catch (e) {
      debugPrint('SK EQ: tray icon unavailable: $e');
      return false;
    }
  }

  /// Keeps the menu's checkmark in sync with the app.
  void setEqEnabled(bool enabled) {
    _eqItem?.state =
        enabled ? tray.MenuItemState.checked : tray.MenuItemState.unchecked;
  }

  void dispose() {
    _icon?.dispose();
    _menu?.dispose();
    _icon = null;
    _menu = null;
    _eqItem = null;
  }

  static tray.MenuItem? _item(
      String label, tray.MenuItemType type, VoidCallback onClick) {
    final item = tray.MenuItem.createWithLabelAndType(label, type);
    item?.addListener((event) {
      if (event is tray.MenuItemClickedEvent) onClick();
    });
    return item;
  }
}
