import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the window can currently be seen. HomePage sets it from window
/// events (minimize / restore, hide-to-tray / show); the spectrum pauses its
/// animation while it is false, so a hidden PureEQ costs no CPU or GPU.
final windowVisibleProvider = StateProvider<bool>((ref) => true);
