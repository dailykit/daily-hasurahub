ALTER TABLE "products"."inventoryProduct" ADD COLUMN "importHistoryId" jsonb;
ALTER TABLE "products"."inventoryProduct" ALTER COLUMN "importHistoryId" DROP NOT NULL;
