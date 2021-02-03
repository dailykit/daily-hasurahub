CREATE OR REPLACE FUNCTION "simpleRecipe"."getRecipeRichResult"(recipe "simpleRecipe"."simpleRecipe")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    res jsonb := '{ "@context": "https://schema.org/", "@type": "Recipe" }';
    yield record;
    sachet record;
    ingredients text[];
    steps jsonb[];
    proc jsonb;
    step jsonb;
BEGIN
    res := res || jsonb_build_object('name', recipe.name, 'image', COALESCE(recipe.image, ''), 'keywords', recipe.name, 'recipeCuisine', recipe.cuisine);
    IF recipe.description IS NOT NULL THEN
        res := res || jsonb_build_object('description', recipe.description);
    END IF;
    IF recipe.author IS NOT NULL THEN
        res := res || jsonb_build_object('author', jsonb_build_object('@type', 'Person', 'name', recipe.author));
    END IF;
    IF recipe."cookingTime" IS NOT NULL THEN
        res := res || jsonb_build_object('cookTime', 'PT' || recipe."cookingTime" || 'M');
    END IF;
    IF recipe."showIngredients" = true THEN
        SELECT * FROM "simpleRecipe"."simpleRecipeYield" WHERE "simpleRecipeId" = recipe.id ORDER BY yield DESC LIMIT 1 INTO yield; 
        IF yield IS NOT NULL THEN
            res := res || jsonb_build_object('recipeYield', yield.yield->>'serving');
            FOR sachet IN SELECT * FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = yield.id LOOP
                SELECT array_append(ingredients, sachet."slipName") INTO ingredients;
            END LOOP;
            res := res || jsonb_build_object('recipeIngredient', ingredients);
        END IF;
    END IF;
    IF recipe."showProcedures" = true AND recipe."procedures" IS NOT NULL THEN
        FOR proc IN SELECT * FROM jsonb_array_elements(recipe."procedures") LOOP
            FOR step IN SELECT * FROM jsonb_array_elements(proc->'steps') LOOP
                SELECT array_append(steps, jsonb_build_object('@type', 'HowToStep', 'name', step->>'title', 'text', step->>'description', 'image', step->'assets'->'images'->0->>'url')) INTO steps;
            END LOOP;
        END LOOP;
        res := res || jsonb_build_object('recipeInstructions', steps);
    END IF;
    return res;
END;
$function$;
