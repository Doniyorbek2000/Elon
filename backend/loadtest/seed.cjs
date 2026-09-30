'use strict';
// Fills a DATABASE with synthetic sellers and active listings so feed/search have realistic volume.
//   npm run build && DATABASE_URL=… node loadtest/seed.cjs [listings=20000]
const { PrismaClient } = require('@prisma/client');
const { buildSearchText } = require('../dist/src/common/text');

const COUNT = Number(process.argv[2] || 20000);
const SELLERS = 200;
const BRANDS = [
  'iPhone 13',
  'Samsung Galaxy A54',
  'Xiaomi Redmi Note 12',
  'Chevrolet Cobalt',
  'Nexia 3',
  'Kia K5',
  'MacBook Air',
  'Lenovo IdeaPad',
  'Sony PlayStation 5',
  'Kvartira 3 xonali',
  'Hovli uy',
  'Divan burchak',
  'Muzlatgich LG',
  'Konditsioner Samsung',
  'Velosiped',
];
const WORDS = [
  'yangi',
  'a’lo holatda',
  'arzon',
  'shoshilinch',
  'kafolat bilan',
  'qutisi bor',
  'bir egasi',
  'savdolashish mumkin',
];

const pick = (list) => list[Math.floor(Math.random() * list.length)];

async function main() {
  const prisma = new PrismaClient();
  const regions = await prisma.region.findMany({ include: { districts: { select: { id: true } } } });
  const categories = await prisma.category.findMany({
    where: { kind: 'MARKETPLACE', children: { none: {} } },
    select: { id: true },
  });
  if (!regions.length || !categories.length) throw new Error('Run migrations and `npm run db:seed` first');

  const existing = await prisma.user.count({ where: { phone: { startsWith: '99899' } } });
  if (existing < SELLERS) {
    for (let i = existing; i < SELLERS; i++) {
      await prisma.user.create({
        data: {
          phone: `99899${String(i).padStart(7, '0')}`,
          phoneVerifiedAt: new Date(),
          profile: { create: { displayName: `Sotuvchi ${i}` } },
        },
      });
    }
  }
  const sellers = await prisma.user.findMany({
    where: { phone: { startsWith: '99899' } },
    select: { id: true },
  });

  const started = Date.now();
  for (let done = 0; done < COUNT; done += 1000) {
    const rows = [];
    for (let i = 0; i < Math.min(1000, COUNT - done); i++) {
      const region = pick(regions);
      const title = `${pick(BRANDS)} ${pick(WORDS)}`;
      const description = `${title}. Holati yaxshi, hujjatlari bor. ${pick(WORDS)}.`;
      const price = BigInt(Math.floor(Math.random() * 200_000_000) + 100_000);
      const published = new Date(Date.now() - Math.floor(Math.random() * 25 * 24 * 3600 * 1000));
      rows.push({
        sellerId: pick(sellers).id,
        categoryId: pick(categories).id,
        title,
        description,
        priceAmount: price,
        priceUzs: price,
        status: 'ACTIVE',
        regionId: region.id,
        districtId: region.districts.length ? pick(region.districts).id : null,
        searchText: buildSearchText(title, description),
        publishedAt: published,
        rankedAt: published,
        expiresAt: new Date(Date.now() + 30 * 24 * 3600 * 1000),
      });
    }
    await prisma.listing.createMany({ data: rows });
    process.stdout.write(`\r${done + rows.length}/${COUNT}`);
  }
  await prisma.$executeRawUnsafe('ANALYZE "Listing"');
  console.log(`\nseeded ${COUNT} listings in ${((Date.now() - started) / 1000).toFixed(1)}s`);
  await prisma.$disconnect();
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
