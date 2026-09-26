import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/presentation/auth_gate.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';

/// Opens (or resumes) a contextual conversation about a listing/job/service.
Future<void> startChat(
  BuildContext context,
  WidgetRef ref, {
  required PublicProfile peer,
  ConversationContext? subject,
}) async {
  if (!await ensureSignedIn(context, ref) || !context.mounted) return;
  if (ref.read(sessionProvider)?.id == peer.id) {
    showAppSnack(context, 'Bu sizning e’loningiz');
    return;
  }
  try {
    final conversation = await ref.read(chatRepositoryProvider).openConversation(peer: peer, context: subject);
    if (context.mounted) await context.push(AppRoutes.chat(conversation.id));
  } on Object {
    if (context.mounted) showAppSnack(context, 'Chatni ochib bo‘lmadi. Qayta urinib ko‘ring.');
  }
}
