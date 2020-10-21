ALTER TABLE "ingredient"."ingredientProcessing" ADD COLUMN "created_at" timestamptz NULL DEFAULT now();
