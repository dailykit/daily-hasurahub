ALTER TABLE "ingredient"."ingredientProcessing" ADD COLUMN "updated_at" timestamptz NULL DEFAULT now();

CREATE OR REPLACE FUNCTION "ingredient"."set_current_timestamp_updated_at"()
RETURNS TRIGGER AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER "set_ingredient_ingredientProcessing_updated_at"
BEFORE UPDATE ON "ingredient"."ingredientProcessing"
FOR EACH ROW
EXECUTE PROCEDURE "ingredient"."set_current_timestamp_updated_at"();
COMMENT ON TRIGGER "set_ingredient_ingredientProcessing_updated_at" ON "ingredient"."ingredientProcessing" 
IS 'trigger to set value of column "updated_at" to current timestamp on row update';
