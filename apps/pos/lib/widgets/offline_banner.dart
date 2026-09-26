import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// `45 min`, `1 h`, `1 h 30 min`. Rounded up, so it reaches 0 only when
/// billing stops.
String formatCountdown(Duration left) {
  final seconds = left.isNegative ? 0 : left.inSeconds;
  final minutes = (seconds + 59) ~/ 60;
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The persistent amber banner on `NearLimit` (03-SYNC §7), counting down to
/// the limit or to the end of a PIN override. It re-reads the device clock
/// every [tick].
class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key, this.tick = const Duration(seconds: 15)});

  final Duration tick;

  static const Color amber = Color(0xFFFFE08A);
  static const Color onAmber = Color(0xFF5C3D00);

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _keepTicking(bool on) {
    if (on && _timer == null) {
      _timer = Timer.periodic(widget.tick, (_) {
        if (mounted) setState(() {});
      });
    } else if (!on) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deadline = ref.watch(offlineViewProvider).deadline;
    _keepTicking(deadline != null);
    if (deadline == null) return const SizedBox.shrink();
    final left = deadline.difference(ref.read(clockProvider)());
    return Material(
      key: const Key('offline-banner'),
      color: OfflineBanner.amber,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, color: OfflineBanner.onAmber),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Connect to internet — billing will stop in '
                '${formatCountdown(left)}',
                key: const Key('offline-banner-text'),
                style: const TextStyle(
                  color: OfflineBanner.onAmber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
