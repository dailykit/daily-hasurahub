ALTER TABLE "ingredient"."modeOfFulfillment" ADD COLUMN "created_at" timestamptz NULL DEFAULT now();
