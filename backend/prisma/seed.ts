import { AttributeType, CategoryKind, PrismaClient, PriceMode } from '@prisma/client';

import { CATEGORY_TREE, CategorySeed, HOME_SHORTCUTS, SERVICE_CATEGORIES } from './data/categories';
import locations from './data/locations.json';
import { PLAN_SEEDS, PRODUCT_SEEDS } from './data/monetization';

const FLAG_KEYS = [
  'monetization',
  'listingTop',
  'listingVip',
  'listingBump',
  'featuredListings',
  'premiumJobs',
  'featuredServices',
  'businessAccounts',
  'businessPlans',
  'ads',
  'coupons',
  'promotionCredits',
];

/**
 * Reference data only (locations, categories, attributes, service
 * categories). Idempotent: safe to run on every deploy. No users, listings
 * or reviews are fabricated here — marketplace content comes from real users.
 */

interface LocalitySeed {
  id: string;
  name: string;
}
interface DistrictSeed {
  id: string;
  name: string;
  lat: number;
  lng: number;
  localities: LocalitySeed[];
}
interface RegionSeed {
  id: string;
  name: string;
  lat: number;
  lng: number;
  districts: DistrictSeed[];
}

async function seedLocations(prisma: PrismaClient): Promise<void> {
  const regions = locations as RegionSeed[];
  for (const [regionIndex, region] of regions.entries()) {
    const regionData = { name: region.name, lat: region.lat, lng: region.lng, sortOrder: regionIndex };
    await prisma.region.upsert({
      where: { id: region.id },
      create: { id: region.id, ...regionData },
      update: regionData,
    });
    for (const district of region.districts) {
      const districtData = { regionId: region.id, name: district.name, lat: district.lat, lng: district.lng };
      await prisma.district.upsert({
        where: { id: district.id },
        create: { id: district.id, ...districtData },
        update: districtData,
      });
      for (const locality of district.localities) {
        const localityData = { districtId: district.id, name: locality.name };
        await prisma.locality.upsert({
          where: { id: locality.id },
          create: { id: locality.id, ...localityData },
          update: localityData,
        });
      }
    }
  }
}

async function seedCategory(
  prisma: PrismaClient,
  category: CategorySeed,
  parentId: string | null,
  sortOrder: number,
): Promise<void> {
  const schema = category.schema ?? { attributes: [] };
  const data = {
    parentId,
    kind: (category.kind ?? 'MARKETPLACE') as CategoryKind,
    name: category.name,
    subtitle: category.subtitle ?? null,
    iconKey: category.iconKey,
    tone: category.tone,
    sortOrder,
    priceMode: (schema.priceMode ?? 'REQUIRED') as PriceMode,
    supportsCondition: schema.supportsCondition ?? true,
    photosRequired: schema.photosRequired ?? true,
    allowUsd: schema.allowUsd ?? false,
    titleHint: schema.titleHint ?? null,
    homeShortcut: parentId === null && HOME_SHORTCUTS.includes(category.id),
    isActive: true,
  };
  await prisma.category.upsert({
    where: { id: category.id },
    create: { id: category.id, ...data },
    update: data,
  });

  for (const [index, attribute] of schema.attributes.entries()) {
    const attributeData = {
      label: attribute.label,
      type: attribute.type as AttributeType,
      required: attribute.required ?? false,
      filterable: attribute.filterable ?? false,
      unit: attribute.unit ?? null,
      min: attribute.min ?? null,
      max: attribute.max ?? null,
      hint: attribute.hint ?? null,
      options: attribute.options ?? [],
      sortOrder: index,
    };
    await prisma.categoryAttribute.upsert({
      where: { categoryId_key: { categoryId: category.id, key: attribute.key } },
      create: { categoryId: category.id, key: attribute.key, ...attributeData },
      update: attributeData,
    });
  }
  // Drop attributes removed from the schema unless listings already use them.
  await prisma.categoryAttribute.deleteMany({
    where: {
      categoryId: category.id,
      key: { notIn: schema.attributes.map((a) => a.key) },
      values: { none: {} },
    },
  });

  for (const [index, child] of (category.children ?? []).entries())
    await seedCategory(prisma, child, category.id, index);
}

async function seedServiceCategories(prisma: PrismaClient): Promise<void> {
  for (const [index, category] of SERVICE_CATEGORIES.entries()) {
    const data = {
      name: category.name,
      iconKey: category.iconKey,
      tone: category.tone,
      sortOrder: index,
      isActive: true,
    };
    await prisma.serviceCategory.upsert({
      where: { id: category.id },
      create: { id: category.id, ...data },
      update: data,
    });
  }
}

/** Create-only: admin changes to flags, plans and products are preserved. */
async function seedMonetization(prisma: PrismaClient): Promise<void> {
  for (const key of FLAG_KEYS) {
    await prisma.featureFlag.upsert({ where: { key }, create: { key, enabled: false }, update: {} });
  }
  for (const plan of PLAN_SEEDS)
    await prisma.plan.upsert({ where: { id: plan.id }, create: plan, update: {} });
  for (const [index, product] of PRODUCT_SEEDS.entries()) {
    await prisma.promotionProduct.upsert({
      where: { id: product.id },
      create: { ...product, placement: product.placement ?? 'NONE', active: false, sortOrder: index },
      update: {},
    });
  }
}

export async function seedReferenceData(prisma: PrismaClient): Promise<void> {
  await seedLocations(prisma);
  for (const [index, root] of CATEGORY_TREE.entries()) await seedCategory(prisma, root, null, index);
  await seedServiceCategories(prisma);
  await seedMonetization(prisma);
}

async function main(prisma: PrismaClient): Promise<void> {
  await seedReferenceData(prisma);
  const [regions, districts, categories, attributes, services] = await Promise.all([
    prisma.region.count(),
    prisma.district.count(),
    prisma.category.count(),
    prisma.categoryAttribute.count(),
    prisma.serviceCategory.count(),
  ]);
  process.stdout.write(
    `Seed complete: ${regions} regions, ${districts} districts, ${categories} categories, ${attributes} attributes, ${services} service categories\n`,
  );
}

if (require.main === module) {
  const prisma = new PrismaClient();
  main(prisma)
    .catch((error: unknown) => {
      process.stderr.write(`Seed failed: ${error instanceof Error ? error.stack : String(error)}\n`);
      process.exitCode = 1;
    })
    .finally(() => void prisma.$disconnect());
}
