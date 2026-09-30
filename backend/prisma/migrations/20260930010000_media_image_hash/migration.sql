-- AlterTable
ALTER TABLE "Media" ADD COLUMN     "hashBand0" INTEGER,
ADD COLUMN     "hashBand1" INTEGER,
ADD COLUMN     "hashBand2" INTEGER,
ADD COLUMN     "hashBand3" INTEGER,
ADD COLUMN     "imageHash" BIGINT;

-- CreateIndex
CREATE INDEX "Media_hashBand0_idx" ON "Media"("hashBand0");

-- CreateIndex
CREATE INDEX "Media_hashBand1_idx" ON "Media"("hashBand1");

-- CreateIndex
CREATE INDEX "Media_hashBand2_idx" ON "Media"("hashBand2");

-- CreateIndex
CREATE INDEX "Media_hashBand3_idx" ON "Media"("hashBand3");

