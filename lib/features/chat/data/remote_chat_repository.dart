import 'dart:async';
import 'dart:math';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/domain/media_image.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../create_listing/domain/media_upload.dart';
import '../domain/chat.dart';

/// Server chat: REST for history (PostgreSQL is the source of truth) and an
/// authenticated Socket.IO channel for realtime events.
///
/// * Sends are optimistic with a client id; retries never duplicate.
/// * On every (re)connect the conversation list and open threads are
///   re-fetched, so messages missed while offline appear.
/// * Identity is only the access token in the handshake.
class RemoteChatRepository implements ChatRepository {
  RemoteChatRepository({
    required ApiClient api,
    required TokenStore tokens,
    required MediaUploadService uploads,
    required String socketOrigin,
    required String? Function() currentUserId,
    required AppLogger logger,
  }) : _api = api,
       _tokens = tokens,
       _uploads = uploads,
       _socketOrigin = socketOrigin,
       _currentUserId = currentUserId,
       _logger = logger;

  final ApiClient _api;
  final TokenStore _tokens;
  final MediaUploadService _uploads;
  final String _socketOrigin;
  final String? Function() _currentUserId;
  final AppLogger _logger;

  io.Socket? _socket;
  bool _disposed = false;

  final _conversationsController = StreamController<List<Conversation>>.broadcast();
  final _messagesChanged = StreamController<String>.broadcast();
  final _typingController = StreamController<(String, bool)>.broadcast();

  List<Conversation>? _conversations;
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, String?> _olderCursor = {};
  final Map<String, Timer> _typingTimers = {};
  final Random _random = Random.secure();

  // ─────────────────────────────────────────────────────────── connection

  void _ensureConnected() {
    if (_socket != null || _disposed) return;
    final socket = io.io(
      '$_socketOrigin/chat',
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(15000)
          .setAuthFn((callback) async => callback({'token': await _tokens.accessToken ?? ''}))
          .build(),
    );
    socket
      ..onConnect((_) => unawaited(_resync()))
      ..onConnectError((Object? error) => unawaited(_handleConnectError(error)))
      ..on('message:new', (data) => _onMessage(data as Map<String, dynamic>))
      ..on('message:read', (data) => _onReceipt(data as Map<String, dynamic>, DeliveryState.read))
      ..on('message:delivered', (data) => _onReceipt(data as Map<String, dynamic>, DeliveryState.delivered))
      ..on('typing', (data) => _onTyping(data as Map<String, dynamic>))
      ..on('presence', (data) => _onPresence(data as Map<String, dynamic>))
      ..connect();
    _socket = socket;
  }

  /// Expired access token: refresh through the API client (its interceptor
  /// rotates tokens), then let Socket.IO reconnect with the new token.
  Future<void> _handleConnectError(Object? error) async {
    final code = error is Map ? error['message'] : '$error';
    if (code == 'SESSION_REVOKED' || code == 'UNAUTHENTICATED' || '$code'.contains('TOKEN')) {
      try {
        await _api.get<Object?>('/conversations/unread-count');
      } on AppFailure {
        // Signed out or offline; reconnection keeps retrying with backoff.
      }
    }
  }

  Future<void> _resync() async {
    try {
      await _refreshConversations();
      for (final conversationId in _messages.keys.toList()) {
        await _refreshLatest(conversationId);
        _socket?.emit('conversation:delivered', {'conversationId': conversationId});
      }
      final peers = {
        for (final c in _conversations ?? const <Conversation>[])
          if (c.peer.id.isNotEmpty) c.peer.id,
      };
      if (peers.isNotEmpty) {
        _socket?.emitWithAck(
          'presence:subscribe',
          {'userIds': peers.take(100).toList()},
          ack: (Object? response) {
            final data = response is Map ? response['data'] : null;
            if (data is List) {
              for (final item in data.cast<Map<String, dynamic>>()) {
                _setPeerOnline(item['userId'] as String, isOnline: item['online'] == true);
              }
            }
          },
        );
      }
    } on AppFailure catch (failure) {
      _logger.warning('Chat resync failed: ${failure.runtimeType}');
    }
  }

  // ─────────────────────────────────────────────────────────── realtime

  void _onMessage(Map<String, dynamic> data) {
    final message = ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
    final conversationId = message.conversationId;
    final mine = message.senderId == _currentUserId();
    if (_messages.containsKey(conversationId)) {
      _upsertMessage(message);
      if (!mine) _socket?.emit('conversation:delivered', {'conversationId': conversationId});
    }
    final conversations = _conversations;
    final index = conversations?.indexWhere((c) => c.id == conversationId) ?? -1;
    if (conversations == null || index < 0) {
      unawaited(_refreshConversations().catchError((Object _) {}));
      return;
    }
    final current = conversations[index];
    final updated = current.copyWith(
      updatedAt: message.sentAt,
      lastMessagePreview: message.preview,
      unreadCount: mine ? 0 : current.unreadCount + 1,
    );
    _publishConversations([updated, ...conversations.where((c) => c.id != conversationId)]);
  }

  void _onReceipt(Map<String, dynamic> data, DeliveryState state) {
    final conversationId = data['conversationId'] as String;
    final at = DateTime.tryParse((data['readAt'] ?? data['deliveredAt'] ?? '') as String);
    final list = _messages[conversationId];
    if (list == null || at == null) return;
    final me = _currentUserId();
    _messages[conversationId] = [
      for (final m in list)
        if (m.senderId == me &&
            !m.sentAt.isAfter(at) &&
            m.delivery.index < state.index &&
            m.delivery != DeliveryState.failed)
          m.copyWith(delivery: state)
        else
          m,
    ];
    _messagesChanged.add(conversationId);
  }

  void _onTyping(Map<String, dynamic> data) {
    final conversationId = data['conversationId'] as String;
    final isTyping = data['isTyping'] == true;
    _typingTimers.remove(conversationId)?.cancel();
    _typingController.add((conversationId, isTyping));
    if (isTyping) {
      // Typing expires unless refreshed (the sender may have gone offline).
      _typingTimers[conversationId] = Timer(
        const Duration(seconds: 6),
        () => _typingController.add((conversationId, false)),
      );
    }
  }

  void _onPresence(Map<String, dynamic> data) =>
      _setPeerOnline(data['userId'] as String, isOnline: data['online'] == true);

  void _setPeerOnline(String userId, {required bool isOnline}) {
    final conversations = _conversations;
    if (conversations == null) return;
    _publishConversations([
      for (final c in conversations)
        c.peer.id == userId ? c.copyWith(peer: _withPresence(c.peer, isOnline: isOnline)) : c,
    ]);
  }

  static PublicProfile _withPresence(PublicProfile p, {required bool isOnline}) => PublicProfile(
    id: p.id,
    name: p.name,
    memberSince: p.memberSince,
    avatar: p.avatar,
    verification: p.verification,
    accountType: p.accountType,
    isOnline: isOnline,
    lastActiveAt: isOnline ? p.lastActiveAt : DateTime.now(),
    rating: p.rating,
    reviewCount: p.reviewCount,
    responseRate: p.responseRate,
    responseTimeMinutes: p.responseTimeMinutes,
    activeListings: p.activeListings,
  );

  // ─────────────────────────────────────────────────────────── state

  void _publishConversations(List<Conversation> next) {
    _conversations = next;
    if (!_conversationsController.isClosed) _conversationsController.add(List.unmodifiable(next));
  }

  /// Keeps messages oldest → newest, deduplicated by id and client id.
  void _upsertMessage(ChatMessage message) {
    final list = [...?_messages[message.conversationId]];
    final index = list.indexWhere(
      (m) => m.id == message.id || (message.clientId != null && m.clientId == message.clientId),
    );
    if (index >= 0) {
      final existing = list[index];
      // Never downgrade a receipt that already arrived.
      list[index] = existing.delivery.index > message.delivery.index && existing.delivery != DeliveryState.failed
          ? message.copyWith(delivery: existing.delivery)
          : message;
    } else {
      list.add(message);
      list.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    }
    _messages[message.conversationId] = list;
    _messagesChanged.add(message.conversationId);
  }

  Future<void> _refreshConversations() async {
    final page = await _api.getPage('/conversations', Conversation.fromJson, query: {'limit': 50});
    _publishConversations(page.items);
  }

  Future<void> _refreshLatest(String conversationId) async {
    final page = await _api.getPage(
      '/conversations/$conversationId/messages',
      ChatMessage.fromJson,
      query: {'limit': 30},
    );
    final pending = [
      for (final m in _messages[conversationId] ?? const <ChatMessage>[])
        if (m.delivery == DeliveryState.sending || m.delivery == DeliveryState.failed) m,
    ];
    final known = _messages[conversationId];
    if (known == null || known.length <= page.items.length) _olderCursor[conversationId] = page.nextCursor;
    for (final message in page.items.reversed) {
      _upsertMessage(message);
    }
    for (final message in pending) {
      if (!(_messages[conversationId] ?? const []).any((m) => m.clientId == message.clientId && m.id != message.id)) {
        _upsertMessage(message);
      }
    }
    _messagesChanged.add(conversationId);
  }

  // ─────────────────────────────────────────────────────────── API

  @override
  Stream<List<Conversation>> watchConversations() async* {
    _ensureConnected();
    if (_conversations == null) await _refreshConversations();
    yield List.unmodifiable(_conversations!);
    yield* _conversationsController.stream;
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) async* {
    _ensureConnected();
    if (!_messages.containsKey(conversationId)) {
      _messages[conversationId] = const [];
      await _refreshLatest(conversationId);
    }
    yield List.unmodifiable(_messages[conversationId]!);
    await for (final changed in _messagesChanged.stream) {
      if (changed == conversationId) yield List.unmodifiable(_messages[conversationId]!);
    }
  }

  @override
  Stream<bool> watchPeerTyping(String conversationId) async* {
    yield false;
    await for (final (id, isTyping) in _typingController.stream) {
      if (id == conversationId) yield isTyping;
    }
  }

  @override
  Future<Conversation> getConversation(String conversationId) async =>
      Conversation.fromJson(await _api.get<JsonMap>('/conversations/$conversationId'));

  @override
  Future<Conversation> openConversation({required PublicProfile peer, ConversationContext? context}) async {
    if (context == null) {
      throw const ValidationFailure('Chat e’lon, vakansiya yoki usta sahifasidan boshlanadi');
    }
    final contextType = switch (context.subject) {
      ConversationSubject.listing => 'listing',
      ConversationSubject.job => 'job',
      ConversationSubject.service => 'service',
      ConversationSubject.candidate => 'candidate',
      ConversationSubject.direct => throw const ValidationFailure('Noma’lum chat turi'),
    };
    final conversation = Conversation.fromJson(
      await _api.post<JsonMap>('/conversations', body: {'contextType': contextType, 'contextId': context.refId}),
    );
    final existing = _conversations;
    if (existing != null) _publishConversations([conversation, ...existing.where((c) => c.id != conversation.id)]);
    return conversation;
  }

  String _newClientId() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<void> sendText(String conversationId, String text) async {
    final message = ChatMessage(
      id: 'local_${_newClientId()}',
      clientId: _newClientId(),
      conversationId: conversationId,
      senderId: _currentUserId() ?? '',
      sentAt: DateTime.now(),
      text: text,
      delivery: DeliveryState.sending,
    );
    _upsertMessage(message);
    await _deliver(message, {'type': 'text', 'text': text});
  }

  @override
  Future<void> sendImage(String conversationId, MediaImage image) async {
    final localPath = image.localPath;
    if (localPath == null) throw const ValidationFailure('Rasm topilmadi');
    final message = ChatMessage(
      id: 'local_${_newClientId()}',
      clientId: _newClientId(),
      conversationId: conversationId,
      senderId: _currentUserId() ?? '',
      sentAt: DateTime.now(),
      kind: MessageKind.image,
      image: image,
      delivery: DeliveryState.sending,
    );
    _upsertMessage(message);
    try {
      final uploaded = await _uploads.upload(localPath, purpose: 'chat').last;
      await _deliver(message, {
        'type': 'image',
        'mediaIds': [uploaded.remoteId],
      });
    } on Object {
      _upsertMessage(message.copyWith(delivery: DeliveryState.failed));
      rethrow;
    }
  }

  @override
  Future<void> retry(String conversationId, ChatMessage message) async {
    if (message.kind != MessageKind.text || message.text == null) return;
    _upsertMessage(message.copyWith(delivery: DeliveryState.sending));
    await _deliver(message, {'type': 'text', 'text': message.text});
  }

  /// Socket when connected (ack), REST otherwise; same client id either way.
  Future<void> _deliver(ChatMessage pending, Map<String, Object?> payload) async {
    final body = {...payload, 'clientId': pending.clientId};
    try {
      final JsonMap sent;
      final socket = _socket;
      if (socket != null && socket.connected) {
        final completer = Completer<JsonMap>();
        socket.emitWithAck(
          'message:send',
          {...body, 'conversationId': pending.conversationId},
          ack: (Object? response) {
            final map = response is Map ? Map<String, dynamic>.from(response) : const <String, dynamic>{};
            if (map['ok'] == true) {
              completer.complete(Map<String, dynamic>.from(map['data'] as Map));
            } else {
              final error = map['error'] is Map ? map['error'] as Map : const {};
              completer.completeError(
                error['code'] == 'BLOCKED'
                    ? const BlockedFailure()
                    : error['code'] == 'RATE_LIMITED'
                    ? const RateLimitFailure()
                    : ValidationFailure(error['message'] as String? ?? 'Xabar yuborilmadi'),
              );
            }
          },
        );
        sent = await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw const TimeoutFailure(),
        );
      } else {
        sent = await _api.post<JsonMap>('/conversations/${pending.conversationId}/messages', body: body);
      }
      final message = ChatMessage.fromJson(sent);
      _upsertMessage(message);
      final conversations = _conversations;
      if (conversations != null) {
        final index = conversations.indexWhere((c) => c.id == pending.conversationId);
        if (index >= 0) {
          final updated = conversations[index].copyWith(updatedAt: message.sentAt, lastMessagePreview: message.preview);
          _publishConversations([updated, ...conversations.where((c) => c.id != pending.conversationId)]);
        }
      }
    } on Object {
      _upsertMessage(pending.copyWith(delivery: DeliveryState.failed));
      rethrow;
    }
  }

  @override
  Future<void> markRead(String conversationId) async {
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit('conversation:read', {'conversationId': conversationId});
    } else {
      await _api.post<Object?>('/conversations/$conversationId/read');
    }
    final conversations = _conversations;
    if (conversations != null) {
      _publishConversations([for (final c in conversations) c.id == conversationId ? c.copyWith(unreadCount: 0) : c]);
    }
  }

  /// Blocking itself goes through the trust & safety repository
  /// (`PUT /blocks/:userId`); this only reflects it in the thread.
  @override
  Future<void> setBlocked(String conversationId, {required bool blocked}) async {
    final conversations = _conversations;
    if (conversations == null) return;
    _publishConversations([for (final c in conversations) c.id == conversationId ? c.copyWith(isBlocked: blocked) : c]);
  }

  @override
  Future<bool> loadOlder(String conversationId) async {
    final cursor = _olderCursor[conversationId];
    if (cursor == null) return false;
    final page = await _api.getPage(
      '/conversations/$conversationId/messages',
      ChatMessage.fromJson,
      query: {'limit': 30},
      cursor: cursor,
    );
    _olderCursor[conversationId] = page.nextCursor;
    for (final message in page.items) {
      _upsertMessage(message);
    }
    return page.nextCursor != null;
  }

  @override
  void sendTyping(String conversationId, {required bool isTyping}) {
    final socket = _socket;
    if (socket != null && socket.connected)
      socket.emit('typing', {'conversationId': conversationId, 'isTyping': isTyping});
  }

  void dispose() {
    _disposed = true;
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _socket?.dispose();
    _socket = null;
    _conversationsController.close();
    _messagesChanged.close();
    _typingController.close();
  }
}
