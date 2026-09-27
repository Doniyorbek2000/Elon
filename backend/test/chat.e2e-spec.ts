import type { Socket } from 'socket.io-client';

import { LogPushProvider } from '../src/modules/notifications/push.provider';
import {
  as,
  connected,
  connectSocket,
  emitAck,
  NAMANGAN_CHUST,
  onceEvent,
  signIn,
  startTestApp,
  stopTestApp,
  TestContext,
  TestUser,
  uploadReadyPhoto,
  waitFor,
} from './helpers';

interface Ack<T> {
  ok: boolean;
  data: T;
  error?: { code: string };
}

interface MessageDto {
  id: string;
  text: string | null;
  senderId: string;
  clientId: string | null;
}

describe('Chat: realtime, persistence, push, safety', () => {
  let ctx: TestContext;
  let seller: TestUser;
  let buyer: TestUser;
  let stranger: TestUser;
  let listingId: string;
  let conversationId: string;
  const sockets: Socket[] = [];

  const socketFor = async (user: TestUser) => {
    const socket = connectSocket(ctx.baseUrl, user.accessToken);
    sockets.push(socket);
    await connected(socket);
    return socket;
  };

  beforeAll(async () => {
    ctx = await startTestApp();
    [seller, buyer, stranger] = await Promise.all([signIn(ctx.http), signIn(ctx.http), signIn(ctx.http)]);
    const photo = await uploadReadyPhoto(ctx.http, seller);
    const listing = await as(ctx.http, seller)
      .post('/listings', {
        categoryId: 'laptops',
        title: 'MacBook Air M1 8/256',
        description: 'Batareya holati 90%, zaryadlovchisi bilan.',
        price: { amount: 7200000, currency: 'uzs' },
        condition: 'used',
        place: NAMANGAN_CHUST,
        mediaIds: [photo],
      })
      .expect(201);
    listingId = listing.body.data.id;
  });

  afterAll(async () => {
    sockets.forEach((s) => s.close());
    await stopTestApp(ctx);
  });

  it('dedupes conversations per (listing, pair) and derives the peer server-side', async () => {
    const first = await as(ctx.http, buyer)
      .post('/conversations', { contextType: 'listing', contextId: listingId })
      .expect(200);
    const second = await as(ctx.http, buyer)
      .post('/conversations', { contextType: 'listing', contextId: listingId })
      .expect(200);
    conversationId = first.body.data.id;
    expect(second.body.data.id).toBe(conversationId);
    expect(first.body.data.peer.id).toBe(seller.userId);
    expect(first.body.data.context).toEqual(
      expect.objectContaining({ subject: 'listing', refId: listingId }),
    );
    // Sellers cannot open a chat with themselves about their own listing.
    await as(ctx.http, seller)
      .post('/conversations', { contextType: 'listing', contextId: listingId })
      .expect(422);
    // Outsiders cannot read the conversation.
    await as(ctx.http, stranger).get(`/conversations/${conversationId}`).expect(404);
    await as(ctx.http, stranger).get(`/conversations/${conversationId}/messages`).expect(404);
    await as(ctx.http, stranger)
      .post(`/conversations/${conversationId}/messages`, { type: 'text', text: 'hi' })
      .expect(404);
  });

  it('flow 4: realtime delivery, typing, read receipts; history survives reconnect', async () => {
    const sellerSocket = await socketFor(seller);
    const buyerSocket = await socketFor(buyer);

    const typing = onceEvent<{ conversationId: string; userId: string }>(sellerSocket, 'typing');
    const typingAck = await emitAck<Ack<null>>(buyerSocket, 'typing', { conversationId, isTyping: true });
    expect(typingAck.ok).toBe(true);
    expect((await typing).userId).toBe(buyer.userId);

    const incoming = onceEvent<{ conversationId: string; message: MessageDto }>(sellerSocket, 'message:new');
    const ack = await emitAck<Ack<MessageDto>>(buyerSocket, 'message:send', {
      conversationId,
      type: 'text',
      text: 'Assalomu alaykum, noutbuk hali sotuvdami?',
      clientId: 'client-msg-1',
    });
    expect(ack.ok).toBe(true);
    const received = await incoming;
    expect(received.message.id).toBe(ack.data.id);
    expect(received.message.senderId).toBe(buyer.userId);

    // Retrying with the same clientId does not duplicate the message.
    const retry = await emitAck<Ack<MessageDto>>(buyerSocket, 'message:send', {
      conversationId,
      type: 'text',
      text: 'Assalomu alaykum, noutbuk hali sotuvdami?',
      clientId: 'client-msg-1',
    });
    expect(retry.data.id).toBe(ack.data.id);

    // The sender identity cannot be spoofed through the payload.
    const spoof = await emitAck<Ack<unknown>>(buyerSocket, 'message:send', {
      conversationId,
      type: 'text',
      text: 'x',
      senderId: seller.userId,
    });
    expect(spoof.ok).toBe(false);
    expect(spoof.error?.code).toBe('VALIDATION_FAILED');

    const read = onceEvent<{ userId: string }>(buyerSocket, 'message:read');
    await emitAck(sellerSocket, 'conversation:read', { conversationId });
    expect((await read).userId).toBe(seller.userId);

    // Disconnect, then reconnect: history and delivery state come from PostgreSQL.
    buyerSocket.close();
    const reconnected = await socketFor(buyer);
    const history = await as(ctx.http, buyer).get(`/conversations/${conversationId}/messages`).expect(200);
    expect(history.body.data).toHaveLength(1);
    expect(history.body.data[0]).toEqual(expect.objectContaining({ id: ack.data.id, delivery: 'read' }));

    const again = onceEvent<{ message: MessageDto }>(reconnected, 'message:new');
    await as(ctx.http, seller)
      .post(`/conversations/${conversationId}/messages`, {
        type: 'text',
        text: 'Ha, sotuvda. Kelib ko‘rishingiz mumkin.',
      })
      .expect(201);
    expect((await again).message.senderId).toBe(seller.userId);
    sellerSocket.close();
    reconnected.close();
  });

  it('paginates message history with a cursor (newest first)', async () => {
    for (let i = 0; i < 5; i++) {
      await as(ctx.http, buyer)
        .post(`/conversations/${conversationId}/messages`, { type: 'text', text: `Savol ${i + 1}` })
        .expect(201);
    }
    const first = await as(ctx.http, buyer)
      .get(`/conversations/${conversationId}/messages?limit=3`)
      .expect(200);
    expect(first.body.data.map((m: MessageDto) => m.text)).toEqual(['Savol 5', 'Savol 4', 'Savol 3']);
    const older = await as(ctx.http, buyer)
      .get(`/conversations/${conversationId}/messages?limit=3&cursor=${first.body.meta.nextCursor}`)
      .expect(200);
    expect(older.body.data.map((m: MessageDto) => m.text)).toEqual([
      'Savol 2',
      'Savol 1',
      'Ha, sotuvda. Kelib ko‘rishingiz mumkin.',
    ]);
    const list = await as(ctx.http, seller).get('/conversations').expect(200);
    expect(list.body.data[0]).toEqual(expect.objectContaining({ id: conversationId, unreadCount: 5 }));
    const unread = await as(ctx.http, seller).get('/conversations/unread-count').expect(200);
    expect(unread.body.data.count).toBe(1);
  });

  it('chat images are private to participants', async () => {
    const res = await as(ctx.http, buyer)
      .upload(await (await import('./helpers')).jpeg(640, 480), 'chat')
      .expect(201);
    const mediaId = res.body.data.id as string;
    await waitFor(
      async () => (await as(ctx.http, buyer).get(`/media/${mediaId}`)).body.data?.status === 'ready',
    );
    await as(ctx.http, buyer)
      .post(`/conversations/${conversationId}/messages`, { type: 'image', mediaIds: [mediaId] })
      .expect(201);
    await as(ctx.http, seller).get(`/media/${mediaId}/feed`).expect(200);
    await as(ctx.http, stranger).get(`/media/${mediaId}/feed`).expect(404);
    // Another user's media cannot be attached.
    await as(ctx.http, seller)
      .post(`/conversations/${conversationId}/messages`, { type: 'image', mediaIds: [mediaId] })
      .expect(422);
  });

  it('flow 5: offline recipients get a push that deep-links into the chat; previews honour privacy', async () => {
    await as(ctx.http, seller)
      .put('/push-devices', { token: `fcm-token-${seller.userId}`, platform: 'android' })
      .expect(200);
    await as(ctx.http, seller).patch('/me', { messagePreviews: false }).expect(200);
    LogPushProvider.outbox.length = 0;
    await as(ctx.http, buyer)
      .post(`/conversations/${conversationId}/messages`, { type: 'text', text: 'Narxi kelishiladimi?' })
      .expect(201);
    const push = await waitFor(async () =>
      LogPushProvider.outbox.find((m) => m.token === `fcm-token-${seller.userId}`),
    );
    expect(push.data.route).toBe(`/chat/${conversationId}`);
    expect(push.data.conversationId).toBe(conversationId);
    expect(push.body).not.toContain('Narxi'); // private preview

    // An online recipient (live socket) gets the realtime event instead of a push.
    const online = await socketFor(seller);
    LogPushProvider.outbox.length = 0;
    await as(ctx.http, buyer)
      .post(`/conversations/${conversationId}/messages`, { type: 'text', text: 'Men yaqinman' })
      .expect(201);
    await new Promise((resolve) => setTimeout(resolve, 600));
    expect(LogPushProvider.outbox).toHaveLength(0);
    online.close();
    await new Promise((resolve) => setTimeout(resolve, 200));

    // Logging out removes the device's push registration.
    await as(ctx.http, seller).post('/auth/logout').expect(200);
    seller = await signIn(ctx.http, seller.phone, 'seller-device-2').catch(async () => {
      const { clearOtpCooldown } = await import('./helpers');
      await clearOtpCooldown(ctx, seller.phone);
      return signIn(ctx.http, seller.phone, 'seller-device-2');
    });
    LogPushProvider.outbox.length = 0;
    await as(ctx.http, buyer)
      .post(`/conversations/${conversationId}/messages`, { type: 'text', text: 'Javob kutyapman' })
      .expect(201);
    await new Promise((resolve) => setTimeout(resolve, 600));
    expect(LogPushProvider.outbox).toHaveLength(0);
  });

  it('presence is only visible to chat partners', async () => {
    const buyerSocket = await socketFor(buyer);
    const strangerSocket = await socketFor(stranger);
    const visible = await emitAck<Ack<Array<{ userId: string; online: boolean }>>>(
      buyerSocket,
      'presence:subscribe',
      { userIds: [seller.userId, stranger.userId] },
    );
    expect(visible.data.map((p) => p.userId)).toEqual([seller.userId]);
    const hidden = await emitAck<Ack<unknown[]>>(strangerSocket, 'presence:subscribe', {
      userIds: [buyer.userId],
    });
    expect(hidden.data).toEqual([]);
    buyerSocket.close();
    strangerSocket.close();
  });

  it('flow 10: blocked users cannot message or open new chats', async () => {
    await as(ctx.http, seller).put(`/blocks/${buyer.userId}`).expect(200);
    const rest = await as(ctx.http, buyer)
      .post(`/conversations/${conversationId}/messages`, { type: 'text', text: 'Salom?' })
      .expect(403);
    expect(rest.body.error.code).toBe('BLOCKED');
    const buyerSocket = await socketFor(buyer);
    const ws = await emitAck<Ack<unknown>>(buyerSocket, 'message:send', {
      conversationId,
      type: 'text',
      text: 'Salom?',
    });
    expect(ws.ok).toBe(false);
    expect(ws.error?.code).toBe('BLOCKED');
    await as(ctx.http, seller)
      .post(`/conversations/${conversationId}/messages`, { type: 'text', text: 'test' })
      .expect(403);
    buyerSocket.close();

    await as(ctx.http, seller).delete(`/blocks/${buyer.userId}`).expect(200);
    await as(ctx.http, buyer)
      .post(`/conversations/${conversationId}/messages`, { type: 'text', text: 'Yana salom' })
      .expect(201);
  });

  it('reports are idempotent per reporter and target', async () => {
    await as(ctx.http, buyer)
      .post('/reports', { targetType: 'listing', targetId: listingId, reason: 'fraud', comment: 'Shubhali' })
      .expect(201);
    await as(ctx.http, buyer)
      .post('/reports', { targetType: 'listing', targetId: listingId, reason: 'spam' })
      .expect(201);
    const { PrismaService } = await import('../src/infra/prisma.service');
    expect(await ctx.app.get(PrismaService).report.count({ where: { targetId: listingId } })).toBe(1);
    await as(ctx.http, buyer)
      .post('/reports', {
        targetType: 'listing',
        targetId: '00000000-0000-4000-8000-000000000000',
        reason: 'fraud',
      })
      .expect(404);
  });
});
