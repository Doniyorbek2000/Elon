import 'package:flutter/foundation.dart';

import '../../../core/domain/media_image.dart';
import '../../../core/domain/public_profile.dart';

/// `candidate`: employer ↔ job seeker about a CV (server context `direct`).
enum ConversationSubject { listing, job, service, candidate, direct }

/// Pinned context card shown at the top of a conversation
/// (listing image, title, price) so both sides know what is discussed.
@immutable
class ConversationContext {
  const ConversationContext({
    required this.subject,
    required this.refId,
    required this.title,
    this.subtitle,
    this.image,
  });

  final ConversationSubject subject;
  final String refId;
  final String title;
  final String? subtitle;
  final MediaImage? image;

  static ConversationContext? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final subject = ConversationSubject.values.firstWhere(
      (s) => s.name == json['subject'],
      orElse: () => ConversationSubject.direct,
    );
    if (subject == ConversationSubject.direct) return null;
    final price = json['price'] as Map<String, dynamic>?;
    return ConversationContext(
      subject: subject,
      refId: json['refId'] as String,
      title: json['title'] as String? ?? '',
      subtitle:
          json['subtitle'] as String? ??
          (price == null
              ? null
              : '${price['amount']} ${price['currency'] == 'usd' ? 'y.e.' : 'so‘m'}'),
      image: json['image'] == null
          ? null
          : MediaImage.fromJson(json['image'] as Map<String, dynamic>),
    );
  }
}

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.peer,
    required this.updatedAt,
    this.context,
    this.lastMessagePreview,
    this.unreadCount = 0,
    this.isBlocked = false,
  });

  final String id;
  final PublicProfile peer;
  final DateTime updatedAt;
  final ConversationContext? context;
  final String? lastMessagePreview;
  final int unreadCount;
  final bool isBlocked;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    peer: json['peer'] == null
        ? PublicProfile(
            id: '',
            name: 'O‘chirilgan foydalanuvchi',
            memberSince: DateTime.fromMillisecondsSinceEpoch(0),
          )
        : PublicProfile.fromJson(json['peer'] as Map<String, dynamic>),
    updatedAt: DateTime.parse(
      (json['lastMessageAt'] ?? json['updatedAt']) as String,
    ),
    context: ConversationContext.fromJson(
      json['context'] as Map<String, dynamic>?,
    ),
    lastMessagePreview: json['lastMessagePreview'] as String?,
    unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    isBlocked: json['isBlocked'] as bool? ?? false,
  );

  Conversation copyWith({
    DateTime? updatedAt,
    String? lastMessagePreview,
    int? unreadCount,
    bool? isBlocked,
    PublicProfile? peer,
  }) => Conversation(
    id: id,
    peer: peer ?? this.peer,
    updatedAt: updatedAt ?? this.updatedAt,
    context: context,
    lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    unreadCount: unreadCount ?? this.unreadCount,
    isBlocked: isBlocked ?? this.isBlocked,
  );
}

enum MessageKind { text, image, listing, system }

enum DeliveryState { sending, sent, delivered, read, failed }

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.sentAt,
    this.kind = MessageKind.text,
    this.text,
    this.image,
    this.sharedRefId,
    this.delivery = DeliveryState.sent,
    this.clientId,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as List<dynamic>? ?? const [];
    final shared = json['sharedListing'] as Map<String, dynamic>?;
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String,
      sentAt: DateTime.parse(json['createdAt'] as String),
      kind: switch (json['type']) {
        'image' => MessageKind.image,
        'listingShare' => MessageKind.listing,
        'system' => MessageKind.system,
        _ => MessageKind.text,
      },
      text: json['text'] as String? ?? shared?['title'] as String?,
      image: images.isEmpty
          ? null
          : MediaImage.fromJson(images.first as Map<String, dynamic>),
      sharedRefId: shared?['id'] as String?,
      delivery: DeliveryState.values.firstWhere(
        (d) => d.name == json['delivery'],
        orElse: () => DeliveryState.sent,
      ),
      clientId: json['clientId'] as String?,
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final DateTime sentAt;
  final MessageKind kind;
  final String? text;
  final MediaImage? image;
  final String? sharedRefId;
  final DeliveryState delivery;

  /// Client-generated id; the server deduplicates retries by it.
  final String? clientId;

  ChatMessage copyWith({DeliveryState? delivery}) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    sentAt: sentAt,
    kind: kind,
    text: text,
    image: image,
    sharedRefId: sharedRefId,
    delivery: delivery ?? this.delivery,
    clientId: clientId,
  );

  String get preview => switch (kind) {
    MessageKind.text || MessageKind.system => text ?? '',
    MessageKind.image => '📷 Rasm',
    MessageKind.listing => '🔗 E’lon',
  };
}

/// Events pushed by the realtime transport (WebSocket in production).
sealed class ChatEvent {
  const ChatEvent(this.conversationId);

  final String conversationId;
}

final class MessageReceived extends ChatEvent {
  const MessageReceived(super.conversationId, this.message);

  final ChatMessage message;
}

final class TypingChanged extends ChatEvent {
  const TypingChanged(
    super.conversationId, {
    required this.userId,
    required this.isTyping,
  });

  final String userId;
  final bool isTyping;
}

final class DeliveryChanged extends ChatEvent {
  const DeliveryChanged(
    super.conversationId, {
    required this.messageIds,
    required this.state,
  });

  final List<String> messageIds;
  final DeliveryState state;
}

final class PresenceChanged extends ChatEvent {
  const PresenceChanged(
    super.conversationId, {
    required this.userId,
    required this.isOnline,
  });

  final String userId;
  final bool isOnline;
}

/// Transport seam: a WebSocket implementation (e.g. `web_socket_channel`)
/// plugs in here when `FeatureFlags.realtimeChatEnabled` is on.
abstract interface class ChatRealtimeGateway {
  Stream<ChatEvent> get events;
  Future<void> connect();
  Future<void> disconnect();
  void sendTyping(String conversationId, {required bool isTyping});
}

abstract interface class ChatRepository {
  Stream<List<Conversation>> watchConversations();
  Stream<List<ChatMessage>> watchMessages(String conversationId);
  Stream<bool> watchPeerTyping(String conversationId);
  Future<Conversation> getConversation(String conversationId);

  /// Returns the existing thread for (peer, context) or creates one.
  Future<Conversation> openConversation({
    required PublicProfile peer,
    ConversationContext? context,
  });
  Future<void> sendText(String conversationId, String text);
  Future<void> sendImage(String conversationId, MediaImage image);
  Future<void> markRead(String conversationId);
  Future<void> setBlocked(String conversationId, {required bool blocked});

  /// Loads the next page of older messages; returns whether more exist.
  Future<bool> loadOlder(String conversationId);

  /// Re-sends a message that failed (same client id → no duplicates).
  Future<void> retry(String conversationId, ChatMessage message);

  /// Ephemeral typing indicator (never persisted).
  void sendTyping(String conversationId, {required bool isTyping});
}
