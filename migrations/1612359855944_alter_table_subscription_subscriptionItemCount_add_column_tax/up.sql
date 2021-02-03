ALTER TABLE "subscription"."subscriptionItemCount" ADD COLUMN "tax" numeric NULL;
ALTER TABLE "subscription"."subscriptionItemCount" ADD COLUMN "isTaxIncluded" boolean NOT NULL DEFAULT false;
ALTER TABLE "subscription"."subscription_zipcode" ADD COLUMN "deliveryTime" jsonb NULL DEFAULT '{"to": "", "from": ""}';
ALTER TABLE "products"."simpleRecipeProduct" ADD COLUMN "additionalText" text NULL;
ALTER TABLE "products"."customizableProduct" ADD COLUMN "additionalText" text NULL;
ALTER TABLE "products"."inventoryProduct" ADD COLUMN "additionalText" text NULL;
ALTER TABLE "products"."inventoryProduct" ADD COLUMN "marketplaceDetails" jsonb NULL;
ALTER TABLE "products"."inventoryProduct" ADD COLUMN "importHistoryId" jsonb NULL;
ALTER TABLE "products"."comboProduct" ADD COLUMN "additionalText" text NULL;
