DROP TRIGGER IF EXISTS "set_ingredient_ingredientProcessing_updated_at" ON "ingredient"."ingredientProcessing";
ALTER TABLE "ingredient"."ingredientProcessing" DROP COLUMN "updated_at";
