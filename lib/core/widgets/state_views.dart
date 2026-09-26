import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_tokens.dart';
import '../errors/app_failure.dart';

/// Illustrated empty/error state. Centered, scroll-safe, scales with text.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.tone = AccentTone.blue,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final AccentTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final pair = palette.tone(tone);
    final circle = compact ? 64.0 : 88.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: compact ? AppSpacing.xl : AppSpacing.huge,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: circle,
                height: circle,
                decoration: BoxDecoration(color: pair.background, shape: BoxShape.circle),
                child: Icon(icon, size: circle * 0.42, color: pair.foreground),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!,
                  style: text.bodyMedium?.copyWith(color: palette.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Maps a failure to friendly copy; offline gets its own illustration.
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final failure = error.asFailure();
    final (icon, title, message, tone) = switch (failure) {
      NetworkFailure() => (
        Icons.wifi_off_rounded,
        'Internet aloqasi yo‘q',
        'Ulanishni tekshirib, qayta urinib ko‘ring. Saqlangan ma’lumotlar ko‘rinib turadi.',
        AccentTone.amber,
      ),
      TimeoutFailure() => (Icons.hourglass_empty_rounded, 'Server javob bermadi', failure.message, AccentTone.amber),
      NotFoundFailure() => (Icons.search_off_rounded, 'Topilmadi', failure.message, AccentTone.slate),
      _ => (Icons.error_outline_rounded, 'Nimadir xato ketdi', failure.message, AccentTone.red),
    };
    return EmptyState(
      icon: icon,
      title: title,
      message: message,
      tone: tone,
      compact: compact,
      actionLabel: onRetry == null ? null : 'Qayta urinish',
      onAction: onRetry,
    );
  }
}

/// Footer for infinite lists: spinner while loading, retry on error.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({super.key, required this.isLoading, required this.hasMore, this.error, this.onRetry});

  final bool isLoading;
  final bool hasMore;
  final AppFailure? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget child;
    if (error != null) {
      child = TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Yana yuklashda xato. Qayta urinish'),
      );
    } else if (isLoading || hasMore) {
      child = const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.4));
    } else {
      child = Text(
        'Hammasi ko‘rsatildi',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textTertiary),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(child: child),
    );
  }
}
