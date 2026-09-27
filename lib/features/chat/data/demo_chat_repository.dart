import 'dart:async';

import '../../../core/domain/media_image.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/demo/demo_database.dart';
import '../domain/chat.dart';

/// In-memory chat backend. Emits over broadcast streams exactly like a
/// WebSocket-fed repository would, including delivery receipts and a
/// simulated peer (typing → reply) when demo latency is enabled.
class DemoChatRepository implements ChatRepository {
  DemoChatRepository(this._db, {required this._clock});

  final DemoDatabase _db;
  final DateTime Function() _clock;
  final _conversationsChanged = StreamController<void>.broadcast();
  final _messagesChanged = StreamController<String>.broadcast();
  final _typing = StreamController<(String, bool)>.broadcast();
  final Set<String> _autoReplied = {};
  final List<Timer> _timers = [];

  String get _me => _db.currentUser?.id ?? 'guest';

  List<Conversation> _sortedConversations() =>
      _db.conversations.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Stream<List<Conversation>> watchConversations() async* {
    await _db.roundTrip(0.6);
    yield _sortedConversations();
    await for (final _ in _conversationsChanged.stream) {
      yield _sortedConversations();
    }
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) async* {
    await _db.roundTrip(0.4);
    yield List.unmodifiable(_db.messages[conversationId] ?? const <ChatMessage>[]);
    await for (final changedId in _messagesChanged.stream) {
      if (changedId == conversationId) yield List.unmodifiable(_db.messages[conversationId] ?? const <ChatMessage>[]);
    }
  }

  @override
  Stream<bool> watchPeerTyping(String conversationId) async* {
    yield false;
    await for (final (id, isTyping) in _typing.stream) {
      if (id == conversationId) yield isTyping;
    }
  }

  @override
  Future<Conversation> getConversation(String conversationId) async {
    await _db.roundTrip(0.3);
    return _db.conversations[conversationId] ?? (throw const NotFoundFailure('Suhbat topilmadi'));
  }

  @override
  Future<Conversation> openConversation({required PublicProfile peer, ConversationContext? context}) async {
    await _db.roundTrip(0.5);
    final existing = _db.conversations.values.where((c) => c.peer.id == peer.id && c.context?.refId == context?.refId);
    if (existing.isNotEmpty) return existing.first;
    final conversation = Conversation(id: _db.nextId('c'), peer: peer, updatedAt: _clock(), context: context);
    _db.conversations[conversation.id] = conversation;
    _db.messages[conversation.id] = [];
    _conversationsChanged.add(null);
    return conversation;
  }

  void _append(String conversationId, ChatMessage message) {
    (_db.messages[conversationId] ??= []).add(message);
    final conversation = _db.conversations[conversationId];
    if (conversation != null) {
      _db.conversations[conversationId] = conversation.copyWith(
        updatedAt: message.sentAt,
        lastMessagePreview: message.preview,
        unreadCount: message.senderId == _me ? conversation.unreadCount : conversation.unreadCount + 1,
      );
    }
    _messagesChanged.add(conversationId);
    _conversationsChanged.add(null);
  }

  void _setDelivery(String conversationId, String messageId, DeliveryState state) {
    final list = _db.messages[conversationId];
    if (list == null) return;
    final index = list.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    list[index] = list[index].copyWith(delivery: state);
    _messagesChanged.add(conversationId);
  }

  void _after(Duration delay, void Function() action) => _timers.add(Timer(delay, action));

  Future<void> _send(String conversationId, ChatMessage message) async {
    final conversation = _db.conversations[conversationId];
    if (conversation == null) throw const NotFoundFailure('Suhbat topilmadi');
    if (conversation.isBlocked) throw const ValidationFailure('Siz bu foydalanuvchini bloklagansiz');
    _append(conversationId, message);
    await _db.roundTrip(0.4);
    _setDelivery(conversationId, message.id, DeliveryState.delivered);
    if (!_db.simulatesPeers) return;
    _after(const Duration(milliseconds: 1400), () => _setDelivery(conversationId, message.id, DeliveryState.read));
    if (_autoReplied.add(conversationId)) {
      _after(const Duration(milliseconds: 1800), () => _typing.add((conversationId, true)));
      _after(const Duration(milliseconds: 4200), () {
        _typing.add((conversationId, false));
        _append(
          conversationId,
          ChatMessage(
            id: _db.nextId('m'),
            conversationId: conversationId,
            senderId: conversation.peer.id,
            text: 'Rahmat, xabaringizni oldim. Tez orada javob beraman.',
            sentAt: _clock(),
          ),
        );
      });
    }
  }

  @override
  Future<void> sendText(String conversationId, String text) => _send(
    conversationId,
    ChatMessage(
      id: _db.nextId('m'),
      conversationId: conversationId,
      senderId: _me,
      text: text.trim(),
      sentAt: _clock(),
      delivery: DeliveryState.sending,
    ),
  );

  @override
  Future<void> sendImage(String conversationId, MediaImage image) => _send(
    conversationId,
    ChatMessage(
      id: _db.nextId('m'),
      conversationId: conversationId,
      senderId: _me,
      kind: MessageKind.image,
      image: image,
      sentAt: _clock(),
      delivery: DeliveryState.sending,
    ),
  );

  @override
  Future<void> markRead(String conversationId) async {
    final conversation = _db.conversations[conversationId];
    if (conversation == null || conversation.unreadCount == 0) return;
    _db.conversations[conversationId] = conversation.copyWith(unreadCount: 0);
    _conversationsChanged.add(null);
  }

  @override
  Future<void> setBlocked(String conversationId, {required bool blocked}) async {
    await _db.roundTrip(0.4);
    final conversation = _db.conversations[conversationId];
    if (conversation == null) return;
    _db.conversations[conversationId] = conversation.copyWith(isBlocked: blocked);
    if (blocked) {
      _db.blockedUserIds.add(conversation.peer.id);
    } else {
      _db.blockedUserIds.remove(conversation.peer.id);
    }
    _conversationsChanged.add(null);
  }

  Future<void> dispose() async {
    for (final timer in _timers) {
      timer.cancel();
    }
    await _conversationsChanged.close();
    await _messagesChanged.close();
    await _typing.close();
  }

  @override
  Future<bool> loadOlder(String conversationId) async => false;

  @override
  Future<void> retry(String conversationId, ChatMessage message) async {
    if (message.text != null) await sendText(conversationId, message.text!);
  }

  @override
  void sendTyping(String conversationId, {required bool isTyping}) {}
}
