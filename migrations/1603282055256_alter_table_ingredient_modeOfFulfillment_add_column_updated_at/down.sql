DROP TRIGGER IF EXISTS "set_ingredient_modeOfFulfillment_updated_at" ON "ingredient"."modeOfFulfillment";
ALTER TABLE "ingredient"."modeOfFulfillment" DROP COLUMN "updated_at";
