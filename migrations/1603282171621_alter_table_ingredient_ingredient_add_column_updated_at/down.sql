DROP TRIGGER IF EXISTS "set_ingredient_ingredient_updated_at" ON "ingredient"."ingredient";
ALTER TABLE "ingredient"."ingredient" DROP COLUMN "updated_at";
