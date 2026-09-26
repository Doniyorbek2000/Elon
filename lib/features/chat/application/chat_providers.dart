import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/clock.dart';
import '../../../data/demo/demo_database.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../data/demo_chat_repository.dart';
import '../domain/chat.dart';

/// Demo transport until the WebSocket gateway ships (see [ChatRealtimeGateway]).
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repository = DemoChatRepository(ref.watch(demoDatabaseProvider), clock: ref.watch(clockProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(chatRepositoryProvider).watchConversations();
});

final unreadChatsCountProvider = Provider<int>((ref) {
  final conversations = ref.watch(conversationsProvider).value ?? const [];
  return conversations.fold(0, (sum, c) => sum + (c.unreadCount > 0 ? 1 : 0));
});

final conversationProvider = Provider.autoDispose.family<AsyncValue<Conversation>, String>((ref, id) {
  final all = ref.watch(conversationsProvider);
  return all.whenData(
    (items) => items.where((c) => c.id == id).firstOrNull ?? (throw StateError('Conversation $id not found')),
  );
});

final messagesProvider = StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, conversationId) {
  return ref.watch(chatRepositoryProvider).watchMessages(conversationId);
});

final peerTypingProvider = StreamProvider.autoDispose.family<bool, String>((ref, conversationId) {
  return ref.watch(chatRepositoryProvider).watchPeerTyping(conversationId);
});

/// One guard per conversation screen instance lifetime.
final messageGuardProvider = Provider.autoDispose.family<MessageGuard, String>((ref, _) => MessageGuard());
