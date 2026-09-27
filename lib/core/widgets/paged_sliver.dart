import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_tokens.dart';

/// Horizontal padding that keeps content within [maxWidth] on tablets while
/// using the standard page gutter on phones.
double adaptiveGutter(
  BuildContext context, {
  double maxWidth = AppBreakpoints.wideContentMaxWidth,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final gutter = AppBreakpoints.pagePadding(context);
  return math.max(gutter, (width - maxWidth) / 2);
}

/// Calls [onLoadMore] when the user scrolls within [threshold] px of the end.
class InfiniteScrollTrigger extends StatelessWidget {
  const InfiniteScrollTrigger({
    super.key,
    required this.child,
    required this.onLoadMore,
    this.threshold = 600,
  });

  final Widget child;
  final VoidCallback onLoadMore;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification is ScrollUpdateNotification &&
            notification.metrics.extentAfter < threshold) {
          onLoadMore();
        }
        return false;
      },
      child: child,
    );
  }
}
