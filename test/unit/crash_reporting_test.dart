import 'package:bozor/core/logging/crash_reporting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('reports nothing about the person or the request', () {
    final event = SentryEvent(
      user: SentryUser(id: 'u1', email: 'a@b.c', ipAddress: '1.2.3.4', username: 'Aziz'),
      request: SentryRequest(url: 'https://api/me', data: {'phone': '998901234567'}, cookies: 'a=b'),
    );
    final scrubbed = CrashReporting.scrub(event, Hint())!;
    expect(scrubbed.user?.id, 'anonymous');
    expect(scrubbed.user?.username, isNull);
    expect(scrubbed.user?.email, isNull);
    expect(scrubbed.user?.ipAddress, isNull);
    expect(scrubbed.request?.data, isNull);
    expect(scrubbed.request?.url, isNull);
    expect(scrubbed.request?.cookies, isNull);
  });

  test('is off without a DSN', () async {
    await CrashReporting.init();
    expect(CrashReporting.enabled, isFalse);
  });
}
