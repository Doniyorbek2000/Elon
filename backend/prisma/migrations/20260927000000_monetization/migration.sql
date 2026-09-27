-- CreateEnum
CREATE TYPE "PromotionKind" AS ENUM ('LISTING_TOP', 'LISTING_VIP', 'LISTING_BUMP', 'LISTING_FEATURED', 'JOB_TOP', 'JOB_FEATURED', 'JOB_URGENT', 'PROVIDER_TOP', 'PROVIDER_FEATURED', 'AD_CAMPAIGN');

-- CreateEnum
CREATE TYPE "PromotionTarget" AS ENUM ('LISTING', 'JOB', 'PROVIDER', 'BUSINESS');

-- CreateEnum
CREATE TYPE "Placement" AS ENUM ('NONE', 'HOME', 'CATEGORY', 'REGION');

-- CreateEnum
CREATE TYPE "ActivationStatus" AS ENUM ('SCHEDULED', 'ACTIVE', 'EXPIRED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "ActivationSource" AS ENUM ('PURCHASE', 'CREDITS', 'PLAN_BENEFIT', 'ADMIN');

-- CreateEnum
CREATE TYPE "BillingPeriod" AS ENUM ('MONTH', 'YEAR');

-- CreateEnum
CREATE TYPE "PurchaseKind" AS ENUM ('PROMOTION', 'SUBSCRIPTION');

-- CreateEnum
CREATE TYPE "PurchaseStatus" AS ENUM ('AWAITING_PAYMENT', 'FULFILLED', 'FAILED', 'CANCELLED', 'REFUNDED', 'NEEDS_REVIEW');

-- CreateEnum
CREATE TYPE "PaymentStatus" AS ENUM ('CREATED', 'PENDING', 'SUCCEEDED', 'FAILED', 'CANCELLED', 'REFUNDED', 'PARTIALLY_REFUNDED');

-- CreateEnum
CREATE TYPE "PaymentProviderKey" AS ENUM ('DEV', 'PAYME', 'CLICK', 'APPLE', 'GOOGLE', 'CREDITS', 'FREE');

-- CreateEnum
CREATE TYPE "RefundStatus" AS ENUM ('REQUESTED', 'SUCCEEDED', 'FAILED', 'MANUAL_REQUIRED');

-- CreateEnum
CREATE TYPE "SubscriptionStatus" AS ENUM ('ACTIVE', 'GRACE_PERIOD', 'PAST_DUE', 'CANCELLED', 'EXPIRED');

-- CreateEnum
CREATE TYPE "CouponDiscountType" AS ENUM ('PERCENT', 'FIXED');

-- CreateEnum
CREATE TYPE "RedemptionStatus" AS ENUM ('RESERVED', 'REDEEMED', 'RELEASED');

-- CreateEnum
CREATE TYPE "CreditEntryType" AS ENUM ('GRANT', 'CONSUME', 'EXPIRE', 'REFUND', 'ADJUST');

-- CreateEnum
CREATE TYPE "AnalyticsLevel" AS ENUM ('BASIC', 'ADVANCED');

-- CreateEnum
CREATE TYPE "BusinessRole" AS ENUM ('OWNER', 'MANAGER');

-- CreateEnum
CREATE TYPE "BusinessVerification" AS ENUM ('NONE', 'PENDING', 'VERIFIED', 'REJECTED');

-- CreateEnum
CREATE TYPE "BusinessStatus" AS ENUM ('ACTIVE', 'SUSPENDED');

-- CreateEnum
CREATE TYPE "AdStatus" AS ENUM ('DRAFT', 'AWAITING_PAYMENT', 'PENDING_REVIEW', 'SCHEDULED', 'ACTIVE', 'PAUSED', 'ENDED', 'REJECTED');

-- CreateEnum
CREATE TYPE "AdDestination" AS ENUM ('LISTING', 'BUSINESS', 'PROVIDER', 'JOB');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "NotificationType" ADD VALUE 'PAYMENT';
ALTER TYPE "NotificationType" ADD VALUE 'PROMOTION';
ALTER TYPE "NotificationType" ADD VALUE 'SUBSCRIPTION';

-- AlterEnum
ALTER TYPE "UserRole" ADD VALUE 'FINANCE';

-- Safety: the legacy promotion columns were never written by any release.
-- Refuse to drop them if that assumption is ever false (no silent data loss).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "Listing" WHERE "promotionType" IS NOT NULL OR "promotedUntil" IS NOT NULL)
     OR EXISTS (SELECT 1 FROM "Job" WHERE "promotionType" IS NOT NULL OR "promotedUntil" IS NOT NULL)
     OR EXISTS (SELECT 1 FROM "ServiceProvider" WHERE "promotionType" IS NOT NULL OR "promotedUntil" IS NOT NULL) THEN
    RAISE EXCEPTION 'Legacy promotion data present; migrate it to PromotionActivation before applying this migration';
  END IF;
END
$$;

-- AlterTable
ALTER TABLE "Job" DROP COLUMN "promotedUntil",
DROP COLUMN "promotionType",
ADD COLUMN     "boostTier" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "boostUntil" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Listing" DROP COLUMN "promotedUntil",
DROP COLUMN "promotionType",
ADD COLUMN     "boostTier" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "boostUntil" TIMESTAMP(3),
ADD COLUMN     "rankedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "ServiceProvider" DROP COLUMN "promotedUntil",
DROP COLUMN "promotionType",
ADD COLUMN     "boostTier" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "boostUntil" TIMESTAMP(3);

-- DropEnum
DROP TYPE "PromotionType";

-- Backfill: organic ranking time starts at the publication time.
UPDATE "Listing" SET "rankedAt" = "publishedAt" WHERE "rankedAt" IS NULL AND "publishedAt" IS NOT NULL;

-- CreateTable
CREATE TABLE "FeatureFlag" (
    "key" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "description" TEXT,
    "updatedById" UUID,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FeatureFlag_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "AppSetting" (
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "description" TEXT,
    "updatedById" UUID,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AppSetting_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "PromotionProduct" (
    "id" TEXT NOT NULL,
    "kind" "PromotionKind" NOT NULL,
    "target" "PromotionTarget" NOT NULL,
    "placement" "Placement" NOT NULL DEFAULT 'NONE',
    "durationDays" INTEGER,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "creditCost" INTEGER,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PromotionProduct_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ProductPrice" (
    "id" UUID NOT NULL,
    "productId" TEXT NOT NULL,
    "amountMinor" BIGINT NOT NULL,
    "currency" "Currency" NOT NULL DEFAULT 'UZS',
    "validFrom" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "validUntil" TIMESTAMP(3),
    "createdById" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProductPrice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Plan" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT false,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "activeListingLimit" INTEGER,
    "monthlyListingLimit" INTEGER,
    "photoLimit" INTEGER NOT NULL DEFAULT 12,
    "activeJobLimit" INTEGER,
    "storefront" BOOLEAN NOT NULL DEFAULT false,
    "businessBadge" BOOLEAN NOT NULL DEFAULT false,
    "analytics" "AnalyticsLevel" NOT NULL DEFAULT 'BASIC',
    "maxManagers" INTEGER NOT NULL DEFAULT 0,
    "monthlyPromotionCredits" INTEGER NOT NULL DEFAULT 0,
    "prioritySupport" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Plan_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PlanPrice" (
    "id" UUID NOT NULL,
    "planId" TEXT NOT NULL,
    "period" "BillingPeriod" NOT NULL,
    "amountMinor" BIGINT NOT NULL,
    "currency" "Currency" NOT NULL DEFAULT 'UZS',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "validFrom" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "validUntil" TIMESTAMP(3),
    "createdById" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PlanPrice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Purchase" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "businessId" UUID,
    "kind" "PurchaseKind" NOT NULL,
    "productId" TEXT,
    "planPriceId" UUID,
    "target" "PromotionTarget",
    "targetId" UUID,
    "placementRegionId" TEXT,
    "placementCategoryId" TEXT,
    "listAmountMinor" BIGINT NOT NULL,
    "discountMinor" BIGINT NOT NULL DEFAULT 0,
    "totalMinor" BIGINT NOT NULL,
    "currency" "Currency" NOT NULL DEFAULT 'UZS',
    "creditsUsed" INTEGER NOT NULL DEFAULT 0,
    "couponId" UUID,
    "status" "PurchaseStatus" NOT NULL DEFAULT 'AWAITING_PAYMENT',
    "platform" TEXT NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "fulfilledAt" TIMESTAMP(3),
    "failureReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Purchase_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Payment" (
    "id" UUID NOT NULL,
    "purchaseId" UUID NOT NULL,
    "provider" "PaymentProviderKey" NOT NULL,
    "status" "PaymentStatus" NOT NULL DEFAULT 'CREATED',
    "amountMinor" BIGINT NOT NULL,
    "currency" "Currency" NOT NULL DEFAULT 'UZS',
    "refundedMinor" BIGINT NOT NULL DEFAULT 0,
    "externalId" TEXT,
    "failureCode" TEXT,
    "succeededAt" TIMESTAMP(3),
    "needsReview" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Payment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PaymentEvent" (
    "id" UUID NOT NULL,
    "provider" "PaymentProviderKey" NOT NULL,
    "eventId" TEXT NOT NULL,
    "paymentId" UUID,
    "source" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "payloadHash" TEXT NOT NULL,
    "outcome" TEXT NOT NULL,
    "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PaymentEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Refund" (
    "id" UUID NOT NULL,
    "paymentId" UUID NOT NULL,
    "amountMinor" BIGINT NOT NULL,
    "status" "RefundStatus" NOT NULL DEFAULT 'REQUESTED',
    "reason" TEXT NOT NULL,
    "providerRefundId" TEXT,
    "requestedById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Refund_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PromotionActivation" (
    "id" UUID NOT NULL,
    "productId" TEXT NOT NULL,
    "kind" "PromotionKind" NOT NULL,
    "target" "PromotionTarget" NOT NULL,
    "targetId" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "purchaseId" UUID,
    "source" "ActivationSource" NOT NULL,
    "placement" "Placement" NOT NULL DEFAULT 'NONE',
    "regionId" TEXT,
    "categoryId" TEXT,
    "status" "ActivationStatus" NOT NULL DEFAULT 'ACTIVE',
    "startsAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3),
    "expiringNotifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PromotionActivation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Subscription" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "businessId" UUID,
    "planId" TEXT NOT NULL,
    "status" "SubscriptionStatus" NOT NULL DEFAULT 'ACTIVE',
    "provider" "PaymentProviderKey" NOT NULL,
    "externalId" TEXT,
    "currentPeriodStart" TIMESTAMP(3) NOT NULL,
    "currentPeriodEnd" TIMESTAMP(3) NOT NULL,
    "graceUntil" TIMESTAMP(3),
    "cancelAtPeriodEnd" BOOLEAN NOT NULL DEFAULT false,
    "cancelledAt" TIMESTAMP(3),
    "lastPurchaseId" UUID,
    "expiringNotifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Subscription_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Coupon" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "description" TEXT,
    "discountType" "CouponDiscountType" NOT NULL,
    "value" BIGINT NOT NULL,
    "currency" "Currency",
    "validFrom" TIMESTAMP(3) NOT NULL,
    "validUntil" TIMESTAMP(3),
    "maxRedemptions" INTEGER,
    "perUserLimit" INTEGER NOT NULL DEFAULT 1,
    "productIds" TEXT[],
    "planIds" TEXT[],
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Coupon_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CouponRedemption" (
    "id" UUID NOT NULL,
    "couponId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "purchaseId" UUID NOT NULL,
    "status" "RedemptionStatus" NOT NULL DEFAULT 'RESERVED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CouponRedemption_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "CreditAccount" (
    "userId" UUID NOT NULL,
    "balance" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "CreditAccount_pkey" PRIMARY KEY ("userId")
);

-- CreateTable
CREATE TABLE "CreditLedgerEntry" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "type" "CreditEntryType" NOT NULL,
    "amount" INTEGER NOT NULL,
    "remaining" INTEGER NOT NULL DEFAULT 0,
    "expiresAt" TIMESTAMP(3),
    "reason" TEXT NOT NULL,
    "subscriptionId" UUID,
    "purchaseId" UUID,
    "activationId" UUID,
    "adminId" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CreditLedgerEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Business" (
    "id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "logoId" UUID,
    "categoryId" TEXT,
    "regionId" TEXT NOT NULL,
    "districtId" TEXT,
    "address" TEXT,
    "phone" TEXT,
    "website" TEXT,
    "telegram" TEXT,
    "openingHours" TEXT,
    "verification" "BusinessVerification" NOT NULL DEFAULT 'NONE',
    "status" "BusinessStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Business_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BusinessMember" (
    "businessId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "role" "BusinessRole" NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BusinessMember_pkey" PRIMARY KEY ("businessId","userId")
);

-- CreateTable
CREATE TABLE "AdCampaign" (
    "id" UUID NOT NULL,
    "businessId" UUID NOT NULL,
    "createdById" UUID NOT NULL,
    "status" "AdStatus" NOT NULL DEFAULT 'DRAFT',
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "imageId" UUID,
    "destination" "AdDestination" NOT NULL,
    "destinationId" UUID NOT NULL,
    "regionId" TEXT,
    "districtId" TEXT,
    "categoryId" TEXT,
    "startsAt" TIMESTAMP(3),
    "endsAt" TIMESTAMP(3),
    "impressionLimit" INTEGER,
    "impressions" INTEGER NOT NULL DEFAULT 0,
    "clicks" INTEGER NOT NULL DEFAULT 0,
    "purchaseId" UUID,
    "rejectReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AdCampaign_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AdDailyStat" (
    "campaignId" UUID NOT NULL,
    "day" DATE NOT NULL,
    "impressions" INTEGER NOT NULL DEFAULT 0,
    "clicks" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "AdDailyStat_pkey" PRIMARY KEY ("campaignId","day")
);

-- CreateTable
CREATE TABLE "ListingDailyStat" (
    "listingId" UUID NOT NULL,
    "day" DATE NOT NULL,
    "views" INTEGER NOT NULL DEFAULT 0,
    "favorites" INTEGER NOT NULL DEFAULT 0,
    "contacts" INTEGER NOT NULL DEFAULT 0,
    "chats" INTEGER NOT NULL DEFAULT 0,
    "shares" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "ListingDailyStat_pkey" PRIMARY KEY ("listingId","day")
);

-- CreateTable
CREATE TABLE "AdminAuditLog" (
    "id" UUID NOT NULL,
    "actorId" UUID NOT NULL,
    "action" TEXT NOT NULL,
    "entity" TEXT NOT NULL,
    "entityId" TEXT,
    "data" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AdminAuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PromotionProduct_target_active_sortOrder_idx" ON "PromotionProduct"("target", "active", "sortOrder");

-- CreateIndex
CREATE INDEX "ProductPrice_productId_validFrom_idx" ON "ProductPrice"("productId", "validFrom" DESC);

-- CreateIndex
CREATE INDEX "PlanPrice_planId_period_validFrom_idx" ON "PlanPrice"("planId", "period", "validFrom" DESC);

-- CreateIndex
CREATE INDEX "Purchase_userId_createdAt_idx" ON "Purchase"("userId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "Purchase_status_createdAt_idx" ON "Purchase"("status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Purchase_userId_idempotencyKey_key" ON "Purchase"("userId", "idempotencyKey");

-- CreateIndex
CREATE INDEX "Payment_status_createdAt_idx" ON "Payment"("status", "createdAt");

-- CreateIndex
CREATE INDEX "Payment_purchaseId_idx" ON "Payment"("purchaseId");

-- CreateIndex
CREATE UNIQUE INDEX "Payment_provider_externalId_key" ON "Payment"("provider", "externalId");

-- CreateIndex
CREATE INDEX "PaymentEvent_paymentId_receivedAt_idx" ON "PaymentEvent"("paymentId", "receivedAt");

-- CreateIndex
CREATE UNIQUE INDEX "PaymentEvent_provider_eventId_key" ON "PaymentEvent"("provider", "eventId");

-- CreateIndex
CREATE INDEX "Refund_paymentId_idx" ON "Refund"("paymentId");

-- CreateIndex
CREATE UNIQUE INDEX "PromotionActivation_purchaseId_key" ON "PromotionActivation"("purchaseId");

-- CreateIndex
CREATE INDEX "PromotionActivation_target_targetId_status_idx" ON "PromotionActivation"("target", "targetId", "status");

-- CreateIndex
CREATE INDEX "PromotionActivation_status_expiresAt_idx" ON "PromotionActivation"("status", "expiresAt");

-- CreateIndex
CREATE INDEX "PromotionActivation_kind_status_placement_regionId_category_idx" ON "PromotionActivation"("kind", "status", "placement", "regionId", "categoryId");

-- CreateIndex
CREATE INDEX "PromotionActivation_ownerId_createdAt_idx" ON "PromotionActivation"("ownerId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "Subscription_userId_status_idx" ON "Subscription"("userId", "status");

-- CreateIndex
CREATE INDEX "Subscription_status_currentPeriodEnd_idx" ON "Subscription"("status", "currentPeriodEnd");

-- CreateIndex
CREATE UNIQUE INDEX "Coupon_code_key" ON "Coupon"("code");

-- CreateIndex
CREATE UNIQUE INDEX "CouponRedemption_purchaseId_key" ON "CouponRedemption"("purchaseId");

-- CreateIndex
CREATE INDEX "CouponRedemption_couponId_userId_status_idx" ON "CouponRedemption"("couponId", "userId", "status");

-- CreateIndex
CREATE INDEX "CreditLedgerEntry_userId_createdAt_idx" ON "CreditLedgerEntry"("userId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "CreditLedgerEntry_type_expiresAt_idx" ON "CreditLedgerEntry"("type", "expiresAt");

-- CreateIndex
CREATE UNIQUE INDEX "Business_ownerId_key" ON "Business"("ownerId");

-- CreateIndex
CREATE INDEX "Business_status_regionId_idx" ON "Business"("status", "regionId");

-- CreateIndex
CREATE INDEX "BusinessMember_userId_idx" ON "BusinessMember"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "AdCampaign_purchaseId_key" ON "AdCampaign"("purchaseId");

-- CreateIndex
CREATE INDEX "AdCampaign_status_regionId_districtId_categoryId_idx" ON "AdCampaign"("status", "regionId", "districtId", "categoryId");

-- CreateIndex
CREATE INDEX "AdCampaign_businessId_createdAt_idx" ON "AdCampaign"("businessId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "AdminAuditLog_entity_entityId_idx" ON "AdminAuditLog"("entity", "entityId");

-- CreateIndex
CREATE INDEX "AdminAuditLog_actorId_createdAt_idx" ON "AdminAuditLog"("actorId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "Listing_status_rankedAt_id_idx" ON "Listing"("status", "rankedAt" DESC, "id");

-- CreateIndex
CREATE INDEX "Listing_status_boostTier_boostUntil_idx" ON "Listing"("status", "boostTier", "boostUntil");

-- AddForeignKey
ALTER TABLE "ProductPrice" ADD CONSTRAINT "ProductPrice_productId_fkey" FOREIGN KEY ("productId") REFERENCES "PromotionProduct"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PlanPrice" ADD CONSTRAINT "PlanPrice_planId_fkey" FOREIGN KEY ("planId") REFERENCES "Plan"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Purchase" ADD CONSTRAINT "Purchase_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Purchase" ADD CONSTRAINT "Purchase_productId_fkey" FOREIGN KEY ("productId") REFERENCES "PromotionProduct"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Purchase" ADD CONSTRAINT "Purchase_planPriceId_fkey" FOREIGN KEY ("planPriceId") REFERENCES "PlanPrice"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_purchaseId_fkey" FOREIGN KEY ("purchaseId") REFERENCES "Purchase"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PaymentEvent" ADD CONSTRAINT "PaymentEvent_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "Payment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Refund" ADD CONSTRAINT "Refund_paymentId_fkey" FOREIGN KEY ("paymentId") REFERENCES "Payment"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PromotionActivation" ADD CONSTRAINT "PromotionActivation_productId_fkey" FOREIGN KEY ("productId") REFERENCES "PromotionProduct"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PromotionActivation" ADD CONSTRAINT "PromotionActivation_purchaseId_fkey" FOREIGN KEY ("purchaseId") REFERENCES "Purchase"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Subscription" ADD CONSTRAINT "Subscription_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Subscription" ADD CONSTRAINT "Subscription_planId_fkey" FOREIGN KEY ("planId") REFERENCES "Plan"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Subscription" ADD CONSTRAINT "Subscription_lastPurchaseId_fkey" FOREIGN KEY ("lastPurchaseId") REFERENCES "Purchase"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CouponRedemption" ADD CONSTRAINT "CouponRedemption_couponId_fkey" FOREIGN KEY ("couponId") REFERENCES "Coupon"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CouponRedemption" ADD CONSTRAINT "CouponRedemption_purchaseId_fkey" FOREIGN KEY ("purchaseId") REFERENCES "Purchase"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CreditAccount" ADD CONSTRAINT "CreditAccount_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "CreditLedgerEntry" ADD CONSTRAINT "CreditLedgerEntry_userId_fkey" FOREIGN KEY ("userId") REFERENCES "CreditAccount"("userId") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Business" ADD CONSTRAINT "Business_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BusinessMember" ADD CONSTRAINT "BusinessMember_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BusinessMember" ADD CONSTRAINT "BusinessMember_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdCampaign" ADD CONSTRAINT "AdCampaign_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "AdDailyStat" ADD CONSTRAINT "AdDailyStat_campaignId_fkey" FOREIGN KEY ("campaignId") REFERENCES "AdCampaign"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Money is never negative; ledger sanity.
ALTER TABLE "ProductPrice" ADD CONSTRAINT "ProductPrice_amount_chk" CHECK ("amountMinor" >= 0);
ALTER TABLE "PlanPrice" ADD CONSTRAINT "PlanPrice_amount_chk" CHECK ("amountMinor" >= 0);
ALTER TABLE "Purchase" ADD CONSTRAINT "Purchase_amounts_chk" CHECK ("listAmountMinor" >= 0 AND "discountMinor" >= 0 AND "totalMinor" >= 0 AND "totalMinor" = "listAmountMinor" - "discountMinor");
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_amounts_chk" CHECK ("amountMinor" >= 0 AND "refundedMinor" >= 0 AND "refundedMinor" <= "amountMinor");
ALTER TABLE "Refund" ADD CONSTRAINT "Refund_amount_chk" CHECK ("amountMinor" > 0);
ALTER TABLE "CreditAccount" ADD CONSTRAINT "CreditAccount_balance_chk" CHECK ("balance" >= 0);
ALTER TABLE "Coupon" ADD CONSTRAINT "Coupon_value_chk" CHECK ("value" > 0 AND ("discountType" <> 'PERCENT' OR "value" <= 100));
