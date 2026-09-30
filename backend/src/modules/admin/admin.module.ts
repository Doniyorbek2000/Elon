import { Body, Controller, Get, Module, Param, ParseUUIDPipe, Patch, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  AnalyticsLevel,
  BillingPeriod,
  BusinessStatus,
  BusinessVerification,
  CouponDiscountType,
  Currency,
  PaymentProviderKey,
  PaymentStatus,
  Placement,
  PromotionKind,
} from '@prisma/client';

import { AuthUser, CurrentUser, Roles } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { Page, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { apiEnum, dbEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { AdsService } from '../business/ads.service';
import { BusinessService } from '../business/business.service';
import { CatalogService, presentEntitlements } from '../monetization/catalog.service';
import { FLAG_KEYS, FlagKey, MonetizationConfig } from '../monetization/config.service';
import { CreditsService } from '../monetization/credits.service';
import { EntitlementService } from '../monetization/entitlements.service';
import { assertWholeMajor, presentAmount } from '../monetization/money';
import { PaymentsService } from '../monetization/payments.service';
import { PromotionService } from '../monetization/promotion.service';
import {
  BusinessStatusDto,
  CouponDto,
  CreditAdjustDto,
  FlagDto,
  PaymentsQuery,
  PriceDto,
  ProductDto,
  ReasonDto,
  RefundDto,
  RevenueQuery,
  SettingDto,
  StoreProductDto,
  UpdateCouponDto,
  UpdatePlanDto,
  UpdateProductDto,
  VerificationDto,
} from './admin.dto';
import { AdminService, validateSetting } from './admin.service';

const TARGET_OF: Record<PromotionKind, 'LISTING' | 'JOB' | 'PROVIDER' | 'BUSINESS'> = {
  LISTING_TOP: 'LISTING',
  LISTING_VIP: 'LISTING',
  LISTING_BUMP: 'LISTING',
  LISTING_FEATURED: 'LISTING',
  JOB_TOP: 'JOB',
  JOB_FEATURED: 'JOB',
  JOB_URGENT: 'JOB',
  PROVIDER_TOP: 'PROVIDER',
  PROVIDER_FEATURED: 'PROVIDER',
  AD_CAMPAIGN: 'BUSINESS',
};

function minor(value: string, currency: Currency): bigint {
  const amount = BigInt(value);
  if (!assertWholeMajor(amount, currency)) throw AppError.validation('Amount must be whole currency units');
  return amount;
}

/**
 * Monetization administration. Catalog/flags: ADMIN only. Money reads and
 * refunds: ADMIN or FINANCE. There are no hidden bypasses: admins cannot mark
 * a payment as paid; they can only refund, cancel activations or grant
 * audited credits.
 */
@ApiTags('admin')
@ApiBearerAuth()
@Roles('ADMIN')
@Controller('admin/monetization')
class AdminMonetizationController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly admin: AdminService,
    private readonly config: MonetizationConfig,
    private readonly catalog: CatalogService,
    private readonly payments: PaymentsService,
    private readonly promotions: PromotionService,
    private readonly credits: CreditsService,
    private readonly entitlements: EntitlementService,
    private readonly business: BusinessService,
    private readonly ads: AdsService,
  ) {}

  // ─── flags & settings

  @Get('flags')
  async flags() {
    const rows = await this.prisma.featureFlag.findMany();
    return FLAG_KEYS.map((key) => ({
      key,
      enabled: rows.find((r) => r.key === key)?.enabled ?? false,
      description: rows.find((r) => r.key === key)?.description ?? null,
    }));
  }

  @Put('flags/:key')
  async setFlag(@CurrentUser() user: AuthUser, @Param('key') key: string, @Body() dto: FlagDto) {
    if (!FLAG_KEYS.includes(key as FlagKey)) throw AppError.notFound('Flag');
    await this.config.setFlag(key as FlagKey, dto.enabled, user.userId, dto.description);
    await this.admin.audit(user.userId, 'flag.set', 'FeatureFlag', key, dto);
    return this.flags();
  }

  @Get('settings/:key')
  setting(@Param('key') key: string) {
    if (!['ranking', 'notices', 'checkoutRoutes'].includes(key)) throw AppError.notFound('Setting');
    return this.config.setting(key as 'ranking');
  }

  @Put('settings/:key')
  async setSetting(@CurrentUser() user: AuthUser, @Param('key') key: string, @Body() dto: SettingDto) {
    const value = validateSetting(key, dto.value);
    await this.config.setSetting(key as 'ranking', value, user.userId);
    await this.admin.audit(user.userId, 'setting.set', 'AppSetting', key, value);
    return this.config.setting(key as 'ranking');
  }

  // ─── store products (App Store / Google Play ids)

  @Get('store-products')
  storeProducts() {
    return this.prisma.storeProduct.findMany({ orderBy: [{ provider: 'asc' }, { storeProductId: 'asc' }] });
  }

  @Put('store-products')
  async setStoreProduct(@CurrentUser() user: AuthUser, @Body() dto: StoreProductDto) {
    if (!!dto.productId === !!dto.planPriceId) {
      throw AppError.validation('Set exactly one of productId or planPriceId');
    }
    if (dto.productId && !(await this.prisma.promotionProduct.findUnique({ where: { id: dto.productId } }))) {
      throw AppError.validation('Unknown productId', { field: 'productId' });
    }
    if (dto.planPriceId && !(await this.prisma.planPrice.findUnique({ where: { id: dto.planPriceId } }))) {
      throw AppError.validation('Unknown planPriceId', { field: 'planPriceId' });
    }
    const row = await this.prisma.storeProduct.upsert({
      where: { provider_storeProductId: { provider: dto.provider, storeProductId: dto.storeProductId } },
      create: {
        provider: dto.provider,
        storeProductId: dto.storeProductId,
        productId: dto.productId,
        planPriceId: dto.planPriceId,
      },
      update: { productId: dto.productId ?? null, planPriceId: dto.planPriceId ?? null },
    });
    await this.admin.audit(user.userId, 'storeProduct.set', 'StoreProduct', row.id, dto);
    return row;
  }

  // ─── catalog

  @Get('products')
  async products() {
    const rows = await this.prisma.promotionProduct.findMany({
      orderBy: [{ target: 'asc' }, { sortOrder: 'asc' }],
      include: { prices: { orderBy: { validFrom: 'desc' }, take: 10 } },
    });
    return rows.map((p) => ({
      id: p.id,
      kind: apiEnum(p.kind),
      target: apiEnum(p.target),
      placement: apiEnum(p.placement),
      durationDays: p.durationDays,
      title: p.title,
      description: p.description,
      creditCost: p.creditCost,
      active: p.active,
      prices: p.prices.map((pr) => ({
        id: pr.id,
        ...presentAmount(pr.amountMinor, pr.currency),
        validFrom: pr.validFrom,
        validUntil: pr.validUntil,
      })),
    }));
  }

  @Post('products')
  async createProduct(@CurrentUser() user: AuthUser, @Body() dto: ProductDto) {
    const kind = dbEnum(dto.kind) as PromotionKind;
    if (kind !== 'LISTING_BUMP' && !dto.durationDays) throw AppError.validation('durationDays is required');
    const placement = dbEnum(dto.placement ?? 'none') as Placement;
    if (kind.endsWith('FEATURED') !== (placement !== 'NONE'))
      throw AppError.validation('Placement is required for featured products only');
    const product = await this.prisma.promotionProduct.create({
      data: {
        id: dto.id,
        kind,
        target: TARGET_OF[kind],
        placement,
        durationDays: kind === 'LISTING_BUMP' ? null : dto.durationDays,
        title: dto.title,
        description: dto.description,
        creditCost: dto.creditCost,
        sortOrder: dto.sortOrder ?? 0,
        active: false, // activated explicitly after a price exists
      },
    });
    await this.admin.audit(user.userId, 'product.create', 'PromotionProduct', product.id, dto);
    return product;
  }

  @Patch('products/:id')
  async updateProduct(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: UpdateProductDto) {
    if (dto.active && !(await this.catalog.currentPrice(id)))
      throw AppError.invalidState('Set a price before activating');
    const product = await this.prisma.promotionProduct.update({ where: { id }, data: dto });
    await this.admin.audit(user.userId, 'product.update', 'PromotionProduct', id, dto);
    return product;
  }

  /** Adds a price row; a future validFrom schedules the change. */
  @Post('products/:id/prices')
  async addProductPrice(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: PriceDto) {
    await this.prisma.promotionProduct.findUniqueOrThrow({ where: { id } });
    const currency = dbEnum(dto.currency) as Currency;
    const price = await this.prisma.productPrice.create({
      data: {
        productId: id,
        amountMinor: minor(dto.amountMinor, currency),
        currency,
        validFrom: dto.validFrom ?? new Date(),
        createdById: user.userId,
      },
    });
    await this.admin.audit(user.userId, 'product.price', 'PromotionProduct', id, dto);
    return { id: price.id, ...presentAmount(price.amountMinor, price.currency), validFrom: price.validFrom };
  }

  @Get('plans')
  async plans() {
    const plans = await this.prisma.plan.findMany({
      orderBy: { sortOrder: 'asc' },
      include: { prices: { orderBy: { validFrom: 'desc' }, take: 10 } },
    });
    return plans.map((p) => ({
      id: p.id,
      title: p.title,
      description: p.description,
      active: p.active,
      entitlements: presentEntitlements(p),
      prices: p.prices.map((pr) => ({
        id: pr.id,
        period: apiEnum(pr.period),
        ...presentAmount(pr.amountMinor, pr.currency),
        validFrom: pr.validFrom,
        active: pr.active,
      })),
    }));
  }

  @Patch('plans/:id')
  async updatePlan(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: UpdatePlanDto) {
    const { analytics, ...rest } = dto;
    const plan = await this.prisma.plan.update({
      where: { id },
      data: { ...rest, ...(analytics ? { analytics: dbEnum(analytics) as AnalyticsLevel } : {}) },
    });
    await this.admin.audit(user.userId, 'plan.update', 'Plan', id, dto);
    await this.entitlements.invalidateAll();
    return plan;
  }

  @Post('plans/:id/prices')
  async addPlanPrice(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: PriceDto) {
    if (!dto.period) throw AppError.validation('period is required');
    if (id === 'FREE') throw AppError.validation('The free plan has no price');
    await this.prisma.plan.findUniqueOrThrow({ where: { id } });
    const currency = dbEnum(dto.currency) as Currency;
    const price = await this.prisma.planPrice.create({
      data: {
        planId: id,
        period: dbEnum(dto.period) as BillingPeriod,
        amountMinor: minor(dto.amountMinor, currency),
        currency,
        validFrom: dto.validFrom ?? new Date(),
        createdById: user.userId,
      },
    });
    await this.admin.audit(user.userId, 'plan.price', 'Plan', id, dto);
    return {
      id: price.id,
      period: apiEnum(price.period),
      ...presentAmount(price.amountMinor, price.currency),
      validFrom: price.validFrom,
    };
  }

  // ─── coupons

  @Get('coupons')
  async coupons() {
    const rows = await this.prisma.coupon.findMany({
      orderBy: { createdAt: 'desc' },
      take: 100,
      include: { _count: { select: { redemptions: { where: { status: 'REDEEMED' } } } } },
    });
    return rows.map((c) => ({
      ...c,
      value: c.value.toString(),
      discountType: apiEnum(c.discountType),
      redeemed: c._count.redemptions,
    }));
  }

  @Post('coupons')
  async createCoupon(@CurrentUser() user: AuthUser, @Body() dto: CouponDto) {
    const discountType = dbEnum(dto.discountType) as CouponDiscountType;
    const value = BigInt(dto.value);
    if (discountType === 'PERCENT' && (value < 1n || value > 100n))
      throw AppError.validation('Percent must be 1..100');
    const currency = dto.currency ? (dbEnum(dto.currency) as Currency) : null;
    if (discountType === 'FIXED' && (!currency || !assertWholeMajor(value, currency)))
      throw AppError.validation('Fixed coupons need a currency and whole amount');
    const coupon = await this.prisma.coupon.create({
      data: {
        code: dto.code,
        description: dto.description,
        discountType,
        value,
        currency,
        validFrom: dto.validFrom,
        validUntil: dto.validUntil,
        maxRedemptions: dto.maxRedemptions,
        perUserLimit: dto.perUserLimit ?? 1,
        productIds: dto.productIds ?? [],
        planIds: dto.planIds ?? [],
        createdById: user.userId,
      },
    });
    await this.admin.audit(user.userId, 'coupon.create', 'Coupon', coupon.id, dto);
    return { ...coupon, value: coupon.value.toString() };
  }

  @Patch('coupons/:id')
  async updateCoupon(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateCouponDto,
  ) {
    const coupon = await this.prisma.coupon.update({ where: { id }, data: dto });
    await this.admin.audit(user.userId, 'coupon.update', 'Coupon', id, dto);
    return { ...coupon, value: coupon.value.toString() };
  }

  // ─── businesses & ads

  @Get('businesses')
  businesses(@Query('verification') verification?: string) {
    return this.prisma.business.findMany({
      where: verification ? { verification: dbEnum(verification) as BusinessVerification } : {},
      orderBy: { updatedAt: 'desc' },
      take: 100,
    });
  }

  @Patch('businesses/:id/verification')
  async verify(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: VerificationDto,
  ) {
    const result = await this.business.setVerification(id, dbEnum(dto.verification) as BusinessVerification);
    await this.admin.audit(user.userId, 'business.verification', 'Business', id, dto);
    return result;
  }

  @Patch('businesses/:id/status')
  async businessStatus(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: BusinessStatusDto,
  ) {
    const result = await this.prisma.business.update({
      where: { id },
      data: { status: dbEnum(dto.status) as BusinessStatus },
    });
    await this.entitlements.invalidateBusiness(id);
    await this.admin.audit(user.userId, 'business.status', 'Business', id, dto);
    return result;
  }

  @Get('campaigns')
  campaigns(@Query('status') status?: string) {
    return this.prisma.adCampaign.findMany({
      where: status ? { status: dbEnum(status) as never } : {},
      orderBy: { updatedAt: 'desc' },
      take: 100,
    });
  }

  @Post('campaigns/:id/approve')
  async approve(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    const result = await this.ads.approve(id);
    await this.admin.audit(user.userId, 'campaign.approve', 'AdCampaign', id);
    return result;
  }

  @Post('campaigns/:id/reject')
  async reject(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReasonDto,
  ) {
    await this.ads.reject(id, dto.reason);
    await this.admin.audit(user.userId, 'campaign.reject', 'AdCampaign', id, dto);
    return { ok: true };
  }

  // ─── activations & credits

  @Get('activations')
  activations(@Query('targetId') targetId?: string) {
    return this.prisma.promotionActivation.findMany({
      where: targetId ? { targetId } : {},
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  }

  @Post('activations/:id/cancel')
  async cancelActivation(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReasonDto,
  ) {
    await this.prisma.$transaction((tx) => this.promotions.cancel(tx, id));
    await this.admin.audit(user.userId, 'activation.cancel', 'PromotionActivation', id, dto);
    return { ok: true };
  }

  @Post('users/:id/credits')
  async adjustCredits(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CreditAdjustDto,
  ) {
    if (dto.amount === 0) throw AppError.validation('Amount must not be zero');
    await this.credits.adjust(id, dto.amount, dto.reason, user.userId);
    await this.admin.audit(user.userId, 'credits.adjust', 'CreditAccount', id, dto);
    return this.credits.summary(id);
  }

  // ─── payments (ADMIN or FINANCE)

  @Roles('ADMIN', 'FINANCE')
  @Get('payments')
  async paymentsList(@Query() query: PaymentsQuery) {
    const take = pageSize(query.limit);
    const rows = await this.prisma.payment.findMany({
      where: {
        ...(query.status ? { status: dbEnum(query.status) as PaymentStatus } : {}),
        ...(query.provider ? { provider: dbEnum(query.provider) as PaymentProviderKey } : {}),
        ...(query.needsReview != null ? { needsReview: query.needsReview } : {}),
        ...keysetWhere(query.cursor),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
      include: {
        purchase: { select: { id: true, userId: true, kind: true, productId: true, status: true } },
      },
    });
    const page = keysetPage(rows, take, (r) => r.createdAt);
    return new Page(
      page.items.map((p) => AdminMonetizationController.presentPayment(p)),
      page.nextCursor,
    );
  }

  @Roles('ADMIN', 'FINANCE')
  @Get('payments/:id')
  async payment(@Param('id', ParseUUIDPipe) id: string) {
    const payment = await this.prisma.payment.findUnique({
      where: { id },
      include: { purchase: true, events: { orderBy: { receivedAt: 'asc' } }, refunds: true },
    });
    if (!payment) throw AppError.notFound('Payment');
    return {
      ...AdminMonetizationController.presentPayment(payment),
      events: payment.events.map((e) => ({
        eventId: e.eventId,
        source: e.source,
        type: e.type,
        outcome: e.outcome,
        receivedAt: e.receivedAt,
      })),
      refunds: payment.refunds.map((r) => ({
        id: r.id,
        status: apiEnum(r.status),
        amountMinor: r.amountMinor.toString(),
        reason: r.reason,
        createdAt: r.createdAt,
      })),
    };
  }

  @Roles('ADMIN', 'FINANCE')
  @Post('payments/:id/refunds')
  async refund(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RefundDto,
  ) {
    const refund = await this.payments.refund({
      paymentId: id,
      amountMinor: dto.amountMinor ? BigInt(dto.amountMinor) : undefined,
      reason: dto.reason,
      actorId: user.userId,
      overridePolicy: dto.overridePolicy ?? false,
    });
    await this.admin.audit(
      user.userId,
      dto.overridePolicy ? 'payment.refund.override' : 'payment.refund',
      'Payment',
      id,
      dto,
    );
    return { id: refund.id, status: apiEnum(refund.status), amountMinor: refund.amountMinor.toString() };
  }

  @Roles('ADMIN', 'FINANCE')
  @Post('refunds/:id/complete')
  async completeRefund(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    const refund = await this.payments.completeManualRefund(id);
    await this.admin.audit(user.userId, 'refund.complete', 'Refund', id);
    return { id: refund.id, status: apiEnum(refund.status) };
  }

  @Roles('ADMIN', 'FINANCE')
  @Get('revenue')
  revenue(@Query() query: RevenueQuery) {
    return this.admin.revenue(query.from, query.to, query.groupBy ?? 'day');
  }

  @Roles('ADMIN', 'FINANCE')
  @Post('reconcile')
  async reconcile(@CurrentUser() user: AuthUser) {
    const result = await this.payments.reconcile();
    await this.admin.audit(user.userId, 'payments.reconcile', 'Payment', null, result);
    return result;
  }

  static presentPayment(p: {
    id: string;
    provider: PaymentProviderKey;
    status: PaymentStatus;
    amountMinor: bigint;
    refundedMinor: bigint;
    currency: Currency;
    externalId: string | null;
    needsReview: boolean;
    createdAt: Date;
    succeededAt: Date | null;
    purchase: { id: string; userId: string; kind: string; productId: string | null; status: string };
  }) {
    return {
      id: p.id,
      provider: apiEnum(p.provider),
      status: apiEnum(p.status),
      amount: presentAmount(p.amountMinor, p.currency),
      refunded: presentAmount(p.refundedMinor, p.currency),
      externalId: p.externalId,
      needsReview: p.needsReview,
      createdAt: p.createdAt,
      succeededAt: p.succeededAt,
      purchase: {
        id: p.purchase.id,
        userId: p.purchase.userId,
        kind: apiEnum(p.purchase.kind),
        productId: p.purchase.productId,
        status: apiEnum(p.purchase.status),
      },
    };
  }
}

@Module({ controllers: [AdminMonetizationController], providers: [AdminService] })
export class AdminModule {}
