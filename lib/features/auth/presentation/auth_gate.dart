import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../application/session_controller.dart';

/// Browsing is anonymous; contacting/posting requires a verified phone.
/// Returns true when the user is (or just became) signed in.
Future<bool> ensureSignedIn(BuildContext context, WidgetRef ref) async {
  if (ref.read(sessionProvider) != null) return true;
  final result = await context.push<bool>(AppRoutes.verifyPhone);
  return result ?? false;
}
