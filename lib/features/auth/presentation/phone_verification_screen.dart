import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart' show ContentWidth;
import '../application/session_controller.dart';
import '../data/demo_auth_repository.dart';

/// Phone → SMS code sign-in. Pops `true` on success, or replaces itself with
/// [next] when reached through an auth redirect.
class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key, this.next});

  final String? next;

  @override
  ConsumerState<PhoneVerificationScreen> createState() => _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends ConsumerState<PhoneVerificationScreen> {
  static const _resendSeconds = 60;

  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String get _fullPhone => '998${UzPhoneInputFormatter.digitsOf(_phone.text)}';

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsLeft <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _requestCode() async {
    if (UzPhoneInputFormatter.digitsOf(_phone.text).length != 9) {
      setState(() => _error = 'Raqamni to‘liq kiriting: 90 123 45 67');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).requestCode(_fullPhone);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _codeSent = true;
      });
      _startTimer();
      _codeFocus.requestFocus();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.asFailure().message;
      });
    }
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) {
      setState(() => _error = '6 xonali kodni kiriting');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).verify(phone: _fullPhone, code: _code.text);
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      final next = widget.next;
      if (next != null) {
        context.pushReplacement(next);
      } else {
        context.pop(true);
      }
    } on Object catch (error) {
      if (!mounted) return;
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _busy = false;
        _error = error.asFailure().message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final demo = ref.watch(appConfigProvider).useDemoData;

    return Scaffold(
      appBar: AppBar(title: const Text('Kirish')),
      body: SafeArea(
        child: ContentWidth(
          maxWidth: AppBreakpoints.formMaxWidth,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            children: [
              const Center(child: BrandMark(size: 64)),
              const SizedBox(height: AppSpacing.xl),
              Text(
                _codeSent ? 'SMS kodni kiriting' : 'Telefon raqamingiz',
                style: text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _codeSent
                    ? '+998 ${_phone.text} raqamiga 6 xonali kod yuborildi'
                    : 'Raqamingiz tasdiqlangach, e’lon joylash, chat va ariza topshirish ochiladi.',
                style: text.bodyMedium?.copyWith(color: palette.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (!_codeSent)
                TextField(
                  controller: _phone,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: const [UzPhoneInputFormatter()],
                  style: text.titleMedium?.copyWith(letterSpacing: 0.5),
                  onSubmitted: (_) => _requestCode(),
                  decoration: InputDecoration(
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
                      child: Text('+998', style: text.titleMedium),
                    ),
                    prefixIconConstraints: const BoxConstraints(),
                    hintText: '90 123 45 67',
                    errorText: _error,
                  ),
                )
              else ...[
                TextField(
                  controller: _code,
                  focusNode: _codeFocus,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: text.headlineSmall?.copyWith(letterSpacing: 12),
                  onChanged: (value) {
                    if (value.length == 6) _verify();
                  },
                  decoration: InputDecoration(counterText: '', hintText: '••••••', errorText: _error),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _codeSent = false;
                              _code.clear();
                              _error = null;
                            }),
                      child: const Text('Raqamni o‘zgartirish'),
                    ),
                    TextButton(
                      onPressed: _secondsLeft > 0 || _busy ? null : _requestCode,
                      child: Text(_secondsLeft > 0 ? 'Qayta yuborish ($_secondsLeft)' : 'Qayta yuborish'),
                    ),
                  ],
                ),
                if (demo)
                  Container(
                    margin: const EdgeInsets.only(top: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(color: palette.primarySoft, borderRadius: AppRadii.mdAll),
                    child: Text(
                      'Demo rejim: haqiqiy SMS yuborilmaydi. Kod — ${DemoAuthRepository.demoCode}',
                      style: text.bodySmall?.copyWith(color: palette.primary),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              FilledButton(
                onPressed: _busy ? null : (_codeSent ? _verify : _requestCode),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(_codeSent ? 'Tasdiqlash' : 'Kod olish'),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: palette.textTertiary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Kodni hech kimga aytmang — Bozor.uz xodimlari uni hech qachon so‘ramaydi.',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
