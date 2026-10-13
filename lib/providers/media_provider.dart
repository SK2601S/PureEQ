import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/media_service.dart';

final mediaServiceProvider = Provider<MediaService>((ref) => MediaService());

/// Whether sound is currently playing, judged from the live spectrum (Windows).
/// The play/pause button shows "pause" while true.
final audioPlayingProvider = StateProvider<bool>((ref) => false);
