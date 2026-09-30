-- DropForeignKey
ALTER TABLE "ProductPrice" DROP CONSTRAINT "ProductPrice_productId_fkey";

-- DropForeignKey
ALTER TABLE "PlanPrice" DROP CONSTRAINT "PlanPrice_planId_fkey";

-- DropForeignKey
ALTER TABLE "Purchase" DROP CONSTRAINT "Purchase_userId_fkey";

-- DropForeignKey
ALTER TABLE "Purchase" DROP CONSTRAINT "Purchase_productId_fkey";

-- DropForeignKey
ALTER TABLE "Purchase" DROP CONSTRAINT "Purchase_planPriceId_fkey";

-- DropForeignKey
ALTER TABLE "Payment" DROP CONSTRAINT "Payment_purchaseId_fkey";

-- DropForeignKey
ALTER TABLE "PaymeTransaction" DROP CONSTRAINT "PaymeTransaction_paymentId_fkey";

-- DropForeignKey
ALTER TABLE "PaymentEvent" DROP CONSTRAINT "PaymentEvent_paymentId_fkey";

-- DropForeignKey
ALTER TABLE "Refund" DROP CONSTRAINT "Refund_paymentId_fkey";

-- DropForeignKey
ALTER TABLE "PromotionActivation" DROP CONSTRAINT "PromotionActivation_productId_fkey";

-- DropForeignKey
ALTER TABLE "PromotionActivation" DROP CONSTRAINT "PromotionActivation_purchaseId_fkey";

-- DropForeignKey
ALTER TABLE "Subscription" DROP CONSTRAINT "Subscription_userId_fkey";

-- DropForeignKey
ALTER TABLE "Subscription" DROP CONSTRAINT "Subscription_planId_fkey";

-- DropForeignKey
ALTER TABLE "Subscription" DROP CONSTRAINT "Subscription_lastPurchaseId_fkey";

-- DropForeignKey
ALTER TABLE "CouponRedemption" DROP CONSTRAINT "CouponRedemption_couponId_fkey";

-- DropForeignKey
ALTER TABLE "CouponRedemption" DROP CONSTRAINT "CouponRedemption_purchaseId_fkey";

-- DropForeignKey
ALTER TABLE "CreditAccount" DROP CONSTRAINT "CreditAccount_userId_fkey";

-- DropForeignKey
ALTER TABLE "CreditLedgerEntry" DROP CONSTRAINT "CreditLedgerEntry_userId_fkey";

-- DropForeignKey
ALTER TABLE "AdCampaign" DROP CONSTRAINT "AdCampaign_businessId_fkey";

-- DropForeignKey
ALTER TABLE "AdDailyStat" DROP CONSTRAINT "AdDailyStat_campaignId_fkey";

-- DropIndex
DROP INDEX "Listing_status_boostTier_boostUntil_idx";

-- AlterTable
ALTER TABLE "Listing" DROP COLUMN "boostTier",
DROP COLUMN "boostUntil";

-- AlterTable
ALTER TABLE "Job" DROP COLUMN "boostTier",
DROP COLUMN "boostUntil";

-- AlterTable
ALTER TABLE "ServiceProvider" DROP COLUMN "boostTier",
DROP COLUMN "boostUntil";

-- DropTable
DROP TABLE "FeatureFlag";

-- DropTable
DROP TABLE "AppSetting";

-- DropTable
DROP TABLE "PromotionProduct";

-- DropTable
DROP TABLE "ProductPrice";

-- DropTable
DROP TABLE "Plan";

-- DropTable
DROP TABLE "PlanPrice";

-- DropTable
DROP TABLE "Purchase";

-- DropTable
DROP TABLE "Payment";

-- DropTable
DROP TABLE "PaymeTransaction";

-- DropTable
DROP TABLE "StoreProduct";

-- DropTable
DROP TABLE "PaymentEvent";

-- DropTable
DROP TABLE "Refund";

-- DropTable
DROP TABLE "PromotionActivation";

-- DropTable
DROP TABLE "Subscription";

-- DropTable
DROP TABLE "Coupon";

-- DropTable
DROP TABLE "CouponRedemption";

-- DropTable
DROP TABLE "CreditAccount";

-- DropTable
DROP TABLE "CreditLedgerEntry";

-- DropTable
DROP TABLE "AdCampaign";

-- DropTable
DROP TABLE "AdDailyStat";

-- DropEnum
DROP TYPE "PromotionKind";

-- DropEnum
DROP TYPE "PromotionTarget";

-- DropEnum
DROP TYPE "Placement";

-- DropEnum
DROP TYPE "ActivationStatus";

-- DropEnum
DROP TYPE "ActivationSource";

-- DropEnum
DROP TYPE "BillingPeriod";

-- DropEnum
DROP TYPE "PurchaseKind";

-- DropEnum
DROP TYPE "PurchaseStatus";

-- DropEnum
DROP TYPE "PaymentStatus";

-- DropEnum
DROP TYPE "PaymentProviderKey";

-- DropEnum
DROP TYPE "RefundStatus";

-- DropEnum
DROP TYPE "SubscriptionStatus";

-- DropEnum
DROP TYPE "CouponDiscountType";

-- DropEnum
DROP TYPE "RedemptionStatus";

-- DropEnum
DROP TYPE "CreditEntryType";

-- DropEnum
DROP TYPE "AnalyticsLevel";

-- DropEnum
DROP TYPE "AdStatus";

-- DropEnum
DROP TYPE "AdDestination";

