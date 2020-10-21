CREATE OR REPLACE FUNCTION products."isSimpleRecipeProductValid"(product products."simpleRecipeProduct")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    res json;
    temp json;
    isRecipeValid boolean;
BEGIN
    IF product."simpleRecipeId" IS NULL
        THEN res := json_build_object('status', false, 'error', 'Recipe not provided');
    END IF;
    SELECT "simpleRecipe".isSimpleRecipeValid("simpleRecipe".*) FROM "simpleRecipe"."simpleRecipe" where "simpleRecipe".id = product."simpleRecipeId" into temp;
    SELECT temp->'status' into isRecipeValid;
    IF NOT isRecipeValid
        THEN res := json_build_object('status', false, 'error', 'Recipe is invalid');
    ELSIF product."default" IS NULL
        THEN res := json_build_object('status', false, 'error', 'Default option not provided');
    ELSE
        res := json_build_object('status', true, 'error', '');
    END IF;
    IF (res->>'status')::boolean = false AND product."isPublished" = true
        THEN PERFORM products."unpublishProduct"('simpleRecipeProduct', product.id);
    END IF;
    RETURN res;
END
$function$;
