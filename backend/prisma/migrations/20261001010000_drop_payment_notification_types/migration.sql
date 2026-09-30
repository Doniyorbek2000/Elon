-- Old payment notifications cannot be represented any more.
DELETE FROM "Notification" WHERE "type"::text IN ('PAYMENT', 'PROMOTION', 'SUBSCRIPTION');

-- AlterEnum
BEGIN;
CREATE TYPE "NotificationType_new" AS ENUM ('MESSAGE', 'LISTING_STATUS', 'APPLICATION_RECEIVED', 'APPLICATION_STATUS', 'REVIEW_RECEIVED', 'ACCOUNT', 'SYSTEM');
ALTER TABLE "Notification" ALTER COLUMN "type" TYPE "NotificationType_new" USING ("type"::text::"NotificationType_new");
ALTER TYPE "NotificationType" RENAME TO "NotificationType_old";
ALTER TYPE "NotificationType_new" RENAME TO "NotificationType";
DROP TYPE "NotificationType_old";
COMMIT;

