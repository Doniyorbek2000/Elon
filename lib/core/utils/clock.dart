import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable time source so relative timestamps are deterministic in tests.
typedef Clock = DateTime Function();

final clockProvider = Provider<Clock>((ref) => DateTime.now);
