import {
  Body,
  Controller,
  Get,
  Global,
  Header,
  HttpCode,
  Module,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Req,
} from '@nestjs/common';
import { ApiBearerAuth, ApiExcludeEndpoint, ApiTags } from '@nestjs/swagger';
import { ActivationStatus, ListingStatus, PaymentProviderKey } from '@prisma/client';
import { IsIn, IsString, Length } from 'class-validator';
import type { Request } from 'express';

import { AuthUser, CurrentUser, Public } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { apiEnum } from '../../common/text';
import { env } from '../../config/env';
import { PrismaService } from '../../infra/prisma.service';
import { RedisService } from '../../infra/redis.service';
import { CatalogService, presentEntitlements } from './catalog.service';
import { CatalogQuery, CheckoutDto, PurchasesQuery, QuoteDto } from './checkout.dto';
import { CheckoutService } from './checkout.service';
import { MonetizationConfig } from './config.service';
import { CouponsService } from './coupons.service';
import { CreditsService } from './credits.service';
import { EntitlementService } from './entitlements.service';
import { PaymentsService } from './payments.service';
import { PromotionService } from './promotion.service';
import { DevPaymentProvider } from './providers/dev.provider';
import { PAYMENT_PROVIDERS, PaymentProvider } from './providers/payment-provider';
import { PaymentProviderRegistry } from './providers/providers.registry';
import { UnconfiguredPaymentProvider } from './providers/unconfigured.provider';
import { SubscriptionsService } from './subscriptions.service';

type RawRequest = Request & { rawBody?: Buffer };

class DevCompleteDto {
  @IsIn(['succeeded', 'failed', 'cancelled'])
  outcome!: 'succeeded' | 'failed' | 'cancelled';

  @IsString()
  @Length(32, 32)
  token!: string;
}

// ─────────────────────────────────────────────────────── public config & catalog

@ApiTags('monetization')
@Controller()
class MonetizationController {
  constructor(
    private readonly config: MonetizationConfig,
    private readonly catalog: CatalogService,
    private readonly entitlements: EntitlementService,
    private readonly checkout: CheckoutService,
    private readonly promotions: PromotionService,
    private readonly prisma: PrismaService,
    private readonly credits: CreditsService,
  ) {}

  /** Runtime flags and free-tier limits; the app never hardcodes them. */
  @Public()
  @Get('config')
  async publicConfig() {
    const [flags, free] = await Promise.all([this.config.flags(), this.prisma.plan.findUnique({ where: { id: 'FREE' } })]);
    return { flags, freePlan: free ? presentEntitlements(free) : null };
  }

  @Public()
  @Get('catalog/plans')
  async plans() {
    if (!(await this.config.enabled('businessPlans'))) return [];
    return (await this.catalog.plans()).map((p) => CatalogService.presentPlan(p));
  }

  /** Products for a target with server-side eligibility (ownership, cooldown). */
  @ApiBearerAuth()
  @Get('catalog/promotions')
  async promotionsFor(@CurrentUser() user: AuthUser, @Query() query: CatalogQuery) {
    const target = CheckoutService.targetFromParam(query.target);
    const products = await this.catalog.productsFor(target);
    let eligibility: { eligible: boolean; reason?: string; bumpAvailableAt?: Date | null } = { eligible: true };
    if (query.targetId && target !== 'BUSINESS') {
      const info = await this.promotions.targetInfo(target, query.targetId);
      if (!info || info.ownerId !== user.userId) throw AppError.notFound('Target');
      const { bumpCooldownHours } = await this.config.setting('ranking');
      eligibility = {
        eligible: info.eligible,
        reason: info.eligible ? undefined : 'inactive',
        bumpAvailableAt: info.lastBumpAt ? new Date(info.lastBumpAt.getTime() + bumpCooldownHours * 3600_000) : null,
      };
    }
    const providers = query.platform ? (await this.checkout.routes(query.platform)).map((k) => apiEnum(k)) : [];
    const balance = (await this.prisma.creditAccount.findUnique({ where: { userId: user.userId } }))?.balance ?? 0;
    return {
      products: products.map((p) => CatalogService.presentProduct(p)),
      eligibility,
      providers,
      credits: { balance, enabled: await this.config.enabled('promotionCredits') },
    };
  }

  @ApiBearerAuth()
  @Get('me/entitlements')
  async myEntitlements(@CurrentUser() user: AuthUser) {
    const effective = await this.entitlements.effectivePlan(user.userId);
    const [activeListings, credits] = await Promise.all([
      this.prisma.listing.count({
        where: {
          sellerId: user.userId,
          deletedAt: null,
          status: { in: [ListingStatus.ACTIVE, ListingStatus.PENDING_REVIEW, ListingStatus.RESERVED] },
        },
      }),
      this.prisma.creditAccount.findUnique({ where: { userId: user.userId } }),
    ]);
    return {
      plan: { id: effective.plan.id, title: effective.plan.title },
      entitlements: presentEntitlements(effective.plan as Parameters<typeof presentEntitlements>[0]),
      usage: { activeListings },
      promotionCredits: credits?.balance ?? 0,
      subscriptionId: effective.subscriptionId,
      businessId: effective.businessId,
    };
  }

  @ApiBearerAuth()
  @Get('me/credits')
  credit(@CurrentUser() user: AuthUser) {
    return this.credits.summary(user.userId);
  }

  /** The user's promotions (active and past) with dates. */
  @ApiBearerAuth()
  @Get('me/promotions')
  async myPromotions(@CurrentUser() user: AuthUser) {
    const rows = await this.prisma.promotionActivation.findMany({
      where: { ownerId: user.userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
      include: { product: { select: { title: true } } },
    });
    const now = new Date();
    return rows.map((a) => ({
      id: a.id,
      kind: apiEnum(a.kind),
      title: a.product.title,
      target: apiEnum(a.target),
      targetId: a.targetId,
      status: apiEnum(
        a.status === ActivationStatus.ACTIVE && a.expiresAt && a.expiresAt <= now ? ActivationStatus.EXPIRED : a.status,
      ),
      startsAt: a.startsAt,
      expiresAt: a.expiresAt,
      purchaseId: a.purchaseId,
    }));
  }
}

// ─────────────────────────────────────────────────────── checkout & purchases

@ApiTags('checkout')
@ApiBearerAuth()
@Controller()
class CheckoutController {
  constructor(
    private readonly checkout: CheckoutService,
    private readonly subscriptions: SubscriptionsService,
  ) {}

  @Post('checkout/quote')
  @HttpCode(200)
  quote(@CurrentUser() user: AuthUser, @Body() dto: QuoteDto) {
    return this.checkout.quote(user, dto);
  }

  /** Creates a purchase + payment. Activation happens only after verification. */
  @Post('checkout')
  checkoutCreate(@CurrentUser() user: AuthUser, @Body() dto: CheckoutDto) {
    return this.checkout.checkout(user, dto);
  }

  @Get('me/purchases')
  history(@CurrentUser() user: AuthUser, @Query() query: PurchasesQuery) {
    return this.checkout.history(user.userId, query.cursor, query.limit);
  }

  @Get('me/purchases/:id')
  detail(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.checkout.present(id, user.userId);
  }

  @Post('me/purchases/:id/cancel')
  @HttpCode(200)
  cancel(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.checkout.cancel(user.userId, id);
  }

  @Get('me/subscriptions')
  mySubscriptions(@CurrentUser() user: AuthUser) {
    return this.subscriptions.mine(user.userId);
  }

  @Post('me/subscriptions/:id/cancel')
  @HttpCode(200)
  cancelSubscription(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.subscriptions.cancel(user.userId, id);
  }
}

// ─────────────────────────────────────────────────────── provider webhooks

@ApiTags('payments')
@Controller('payments')
class PaymentWebhookController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly registry: PaymentProviderRegistry,
    private readonly prisma: PrismaService,
  ) {}

  /**
   * Provider callbacks. Signature is verified by the adapter against the raw
   * body before anything is parsed; events are idempotent per provider id.
   */
  @Public()
  @Post('webhooks/:provider')
  @HttpCode(200)
  webhook(@Param('provider') provider: string, @Req() request: RawRequest) {
    const key = this.registry.parseKey(provider);
    if (key === PaymentProviderKey.CREDITS || key === PaymentProviderKey.FREE) throw AppError.notFound('Payment provider');
    return this.payments.handleWebhook(key, {
      headers: request.headers,
      rawBody: request.rawBody ?? Buffer.alloc(0),
    });
  }

  // Dev provider's hosted checkout (development/test only).

  private dev(): DevPaymentProvider {
    const provider = this.registry.get(PaymentProviderKey.DEV) as DevPaymentProvider;
    if (!provider.configured()) throw AppError.notFound('Page');
    return provider;
  }

  @ApiExcludeEndpoint()
  @Public()
  @Get('dev/checkout/:paymentId')
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'no-store')
  async devCheckoutPage(@Param('paymentId', ParseUUIDPipe) paymentId: string, @Query('token') token: string) {
    const provider = this.dev();
    if (token !== provider.pageToken(paymentId)) throw AppError.notFound('Page');
    const payment = await this.prisma.payment.findUnique({ where: { id: paymentId }, include: { purchase: { include: { product: true } } } });
    if (!payment) throw AppError.notFound('Page');
    const amount = (payment.amountMinor / 100n).toString();
    const action = `${env().PUBLIC_API_URL}/api/v1/payments/dev/checkout/${paymentId}/complete`;
    const button = (outcome: string, label: string) =>
      `<button onclick="fetch('${action}',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({outcome:'${outcome}',token:'${token}'})}).then(r=>r.json()).then(()=>{document.body.innerHTML='<p>Natija yuborildi. Ilovaga qayting.</p>'})">${label}</button>`;
    return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Test to'lov</title>
<style>body{font-family:sans-serif;max-width:420px;margin:40px auto;padding:0 16px}button{display:block;width:100%;padding:14px;margin:10px 0;font-size:16px}</style></head>
<body><h2>TEST TO'LOV (haqiqiy emas)</h2><p>${escapeHtml(payment.purchase.product?.title ?? 'Tarif')}</p><p><b>${amount} so'm</b></p>
${button('succeeded', "To'lash (muvaffaqiyatli)")}${button('failed', 'Xato')}${button('cancelled', 'Bekor qilish')}</body></html>`;
  }

  @ApiExcludeEndpoint()
  @Public()
  @Post('dev/checkout/:paymentId/complete')
  @HttpCode(200)
  async devComplete(@Param('paymentId', ParseUUIDPipe) paymentId: string, @Body() dto: DevCompleteDto) {
    const provider = this.dev();
    if (dto.token !== provider.pageToken(paymentId)) throw AppError.notFound('Page');
    const payment = await this.prisma.payment.findUnique({ where: { id: paymentId } });
    if (!payment || payment.provider !== PaymentProviderKey.DEV) throw AppError.notFound('Page');
    // Behaves like the real provider: asynchronously sends a signed webhook.
    const signed = await provider.simulate(payment, dto.outcome);
    await this.payments.handleWebhook(PaymentProviderKey.DEV, signed);
    return { ok: true };
  }
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

@Global()
@Module({
  controllers: [MonetizationController, CheckoutController, PaymentWebhookController],
  providers: [
    MonetizationConfig,
    CatalogService,
    EntitlementService,
    PromotionService,
    CreditsService,
    CouponsService,
    SubscriptionsService,
    PaymentsService,
    CheckoutService,
    PaymentProviderRegistry,
    {
      provide: PAYMENT_PROVIDERS,
      inject: [RedisService],
      useFactory: (redis: RedisService): PaymentProvider[] => [
        new DevPaymentProvider(redis.client),
        // Interfaces only until implemented against official docs with credentials.
        new UnconfiguredPaymentProvider(PaymentProviderKey.PAYME),
        new UnconfiguredPaymentProvider(PaymentProviderKey.CLICK),
        new UnconfiguredPaymentProvider(PaymentProviderKey.APPLE),
        new UnconfiguredPaymentProvider(PaymentProviderKey.GOOGLE),
        new UnconfiguredPaymentProvider(PaymentProviderKey.CREDITS),
        new UnconfiguredPaymentProvider(PaymentProviderKey.FREE),
      ],
    },
  ],
  exports: [
    MonetizationConfig,
    CatalogService,
    EntitlementService,
    PromotionService,
    CreditsService,
    SubscriptionsService,
    PaymentsService,
    CheckoutService,
    PaymentProviderRegistry,
  ],
})
export class MonetizationModule {}
