-- CreateTable
CREATE TABLE "StoreProduct" (
    "id" UUID NOT NULL,
    "provider" "PaymentProviderKey" NOT NULL,
    "storeProductId" TEXT NOT NULL,
    "productId" TEXT,
    "planPriceId" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StoreProduct_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "StoreProduct_provider_productId_idx" ON "StoreProduct"("provider", "productId");

-- CreateIndex
CREATE INDEX "StoreProduct_provider_planPriceId_idx" ON "StoreProduct"("provider", "planPriceId");

-- CreateIndex
CREATE UNIQUE INDEX "StoreProduct_provider_storeProductId_key" ON "StoreProduct"("provider", "storeProductId");

