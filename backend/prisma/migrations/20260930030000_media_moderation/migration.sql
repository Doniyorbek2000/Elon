-- AlterTable
ALTER TABLE "Media" ADD COLUMN     "moderation" TEXT,
ADD COLUMN     "moderationLabels" TEXT[] DEFAULT ARRAY[]::TEXT[];

