import { Payment, PaymentProviderKey, Purchase } from '@prisma/client';

import { PrismaService } from '../../../infra/prisma.service';

/** Resolves the store-side product id a purchase must have been bought with. */
export async function storeProductFor(
  prisma: PrismaService,
  provider: PaymentProviderKey,
  purchase: Pick<Purchase, 'productId' | 'planPriceId'>,
): Promise<string | null> {
  if (!purchase.productId && !purchase.planPriceId) return null;
  const row = await prisma.storeProduct.findFirst({
    where: {
      provider,
      ...(purchase.productId ? { productId: purchase.productId } : { planPriceId: purchase.planPriceId }),
    },
    orderBy: { createdAt: 'desc' },
    select: { storeProductId: true },
  });
  return row?.storeProductId ?? null;
}

export type PaymentLike = Pick<Payment, 'id'>;
