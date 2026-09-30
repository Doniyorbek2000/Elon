'use strict';
// Realtime chat load: PAIRS of users talk through Socket.IO; measures send→ack and send→delivery latency.
//   BASE_URL=http://localhost:3000 node loadtest/chat.cjs [pairs=50] [messagesPerPair=20]
const { PrismaClient } = require('@prisma/client');
const { io } = require('socket.io-client');
const { BASE, call, signIn, percentile } = require('./lib.cjs');

const PAIRS = Number(process.argv[2] || 50);
const MESSAGES = Number(process.argv[3] || 20);

const connect = (token) =>
  new Promise((resolve, reject) => {
    const socket = io(`${BASE}/chat`, { path: '/socket.io', transports: ['websocket'], auth: { token } });
    socket.once('connect', () => resolve(socket));
    socket.once('connect_error', reject);
  });

const emitAck = (socket, event, payload) =>
  new Promise((resolve) => socket.emit(event, payload, (ack) => resolve(ack)));

async function main() {
  // Each pair: a synthetic buyer and the real (seeded) seller of a listing, so both are conversation participants.
  const prisma = new PrismaClient();
  const listings = await prisma.listing.findMany({
    where: { status: 'ACTIVE', seller: { phone: { startsWith: '99899' } } },
    select: { id: true, seller: { select: { phone: true } } },
    distinct: ['sellerId'],
    take: PAIRS,
  });
  await prisma.$disconnect();
  if (listings.length < PAIRS)
    throw new Error(`Need ${PAIRS} sellers with listings: run loadtest/seed.cjs first`);

  const runBase = 100000 + Math.floor(Math.random() * 800000);
  console.log(`signing in ${PAIRS * 2} users…`);
  const users = [];
  for (let i = 0; i < PAIRS; i++) {
    users.push(await signIn(runBase + i), await signIn(runBase + 50000 + i, listings[i].seller.phone));
  }

  const ack = [];
  const delivery = [];
  const sentAtByText = new Map();
  let failures = 0;

  const pairs = await Promise.all(
    Array.from({ length: PAIRS }, async (_, p) => {
      const buyer = users[p * 2];
      const other = users[p * 2 + 1];
      const conversation = await call('POST', '/conversations', {
        token: buyer.accessToken,
        body: { contextType: 'listing', contextId: listings[p].id },
      });
      const [a, b] = await Promise.all([connect(buyer.accessToken), connect(other.accessToken)]);
      b.on('message:new', ({ message }) => {
        const sentAt = sentAtByText.get(`${conversation.id}|${message.text}`);
        if (sentAt !== undefined) delivery.push(performance.now() - sentAt);
      });
      return { conversationId: conversation.id, sender: a, receiver: b };
    }),
  );
  console.log(`${PAIRS} pairs connected, sending ${PAIRS * MESSAGES} messages`);

  const started = Date.now();
  await Promise.all(
    pairs.map(async ({ conversationId, sender }) => {
      for (let m = 0; m < MESSAGES; m++) {
        const sentAt = performance.now();
        const text = `load message ${m}`;
        sentAtByText.set(`${conversationId}|${text}`, sentAt);
        const reply = await emitAck(sender, 'message:send', {
          conversationId,
          type: 'text',
          text,
          clientId: `${conversationId}-${m}-${Date.now()}`,
        });
        if (!reply?.ok) failures++;
        else ack.push(performance.now() - sentAt);
        await new Promise((r) => setTimeout(r, 50 + Math.random() * 100));
      }
    }),
  );
  const seconds = (Date.now() - started) / 1000;

  ack.sort((x, y) => x - y);
  delivery.sort((x, y) => x - y);
  console.log(
    `\nmessages acked: ${ack.length}, failed: ${failures}, ${(ack.length / seconds).toFixed(0)} msg/s`,
  );
  console.log(
    `send→ack ms  p50 ${percentile(ack, 50).toFixed(1)}  p95 ${percentile(ack, 95).toFixed(1)}  p99 ${percentile(ack, 99).toFixed(1)}`,
  );
  await new Promise((r) => setTimeout(r, 500));
  delivery.sort((x, y) => x - y);
  console.log(
    `send→delivered ms  p50 ${percentile(delivery, 50).toFixed(1)}  p95 ${percentile(delivery, 95).toFixed(1)}  p99 ${percentile(delivery, 99).toFixed(1)}  (${delivery.length}/${ack.length} seen by receivers)`,
  );
  pairs.forEach(({ sender, receiver }) => [sender, receiver].forEach((s) => s.close()));
  if (failures > 0 || percentile(ack, 99) > Number(process.env.P99_MS || 500)) process.exit(1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
