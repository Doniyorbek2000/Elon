import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/clock.dart';
import '../../../data/demo/demo_database.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../../auth/application/session_controller.dart';
import '../../create_listing/data/media_services.dart';
import '../data/demo_chat_repository.dart';
import '../data/remote_chat_repository.dart';
import '../domain/chat.dart';

/// Demo data locally; with a backend, REST + authenticated Socket.IO.
/// Rebuilt per signed-in account so nothing leaks across sign-outs.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.useDemoData) {
    final repository = DemoChatRepository(
      ref.watch(demoDatabaseProvider),
      clock: ref.watch(clockProvider),
    );
    ref.onDispose(repository.dispose);
    return repository;
  }
  final userId = ref.watch(sessionProvider.select((user) => user?.id));
  final base = Uri.parse(config.apiBaseUrl);
  final repository = RemoteChatRepository(
    api: ref.watch(apiClientProvider),
    tokens: ref.watch(tokenStoreProvider),
    uploads: ref.watch(mediaUploadServiceProvider),
    socketOrigin: base.origin,
    currentUserId: () => userId,
    logger: ref.watch(appLoggerProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  // Guests have no conversations; avoid opening a socket for them.
  if (!ref.watch(appConfigProvider).useDemoData &&
      ref.watch(sessionProvider) == null) {
    return Stream.value(const []);
  }
  return ref.watch(chatRepositoryProvider).watchConversations();
});

final unreadChatsCountProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationsProvider).value ?? const [];
  return conversations.fold(0, (sum, c) => sum + (c.unreadCount > 0 ? 1 : 0));
});

final conversationProvider = Provider.autoDispose
    .family<AsyncValue<Conversation>, String>((ref, id) {
      final all = ref.watch(conversationsProvider);
      return all.whenData(
        (items) =>
            items.where((c) => c.id == id).firstOrNull ??
            (throw StateError('Conversation $id not found')),
      );
    });

final messagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, conversationId) {
      return ref.watch(chatRepositoryProvider).watchMessages(conversationId);
    });

final peerTypingProvider = StreamProvider.autoDispose.family<bool, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatRepositoryProvider).watchPeerTyping(conversationId);
});

/// One guard per conversation screen instance lifetime.
final messageGuardProvider = Provider.autoDispose.family<MessageGuard, String>(
  (ref, _) => MessageGuard(),
);
