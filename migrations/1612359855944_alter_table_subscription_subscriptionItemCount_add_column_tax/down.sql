ALTER TABLE "subscription"."subscriptionItemCount" DROP COLUMN "tax";
ALTER TABLE "subscription"."subscriptionItemCount" DROP COLUMN "isTaxIncluded";
ALTER TABLE "subscription"."subscription_zipcode" DROP COLUMN "deliveryTime";
ALTER TABLE "products"."simpleRecipeProduct" DROP COLUMN "additionalText";
ALTER TABLE "products"."customizableProduct" DROP COLUMN "additionalText";
ALTER TABLE "products"."inventoryProduct" DROP COLUMN "additionalText";
ALTER TABLE "products"."inventoryProduct" DROP COLUMN "importHistoryId";
ALTER TABLE "products"."comboProduct" DROP COLUMN "additionalText";
