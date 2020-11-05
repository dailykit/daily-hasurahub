CREATE OR REPLACE FUNCTION subscription."cartItem"(x subscription."subscriptionOccurence_product")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    item jsonb;
    productType text;
    productId int;
    optionId int;
BEGIN
    IF x."simpleRecipeProductId" IS NOT NULL THEN
        productType := 'SRP';
    ELSE
        productType := 'IP';
    END IF;
    IF productType = 'SRP' THEN
        SELECT x."simpleRecipeProductId" into productId;
        SELECT x."simpleRecipeProductOptionId" into optionId;
        SELECT products."simpleRecipeProductCartItemById"(productId, optionId) into item;
    ELSE
        SELECT x."inventoryProductId" into productId;
        SELECT x."inventoryProductOptionId" into optionId;
        SELECT products."inventoryProductCartItemById"(productId, optionId) into item;
    END IF;
    RETURN item;
END
$function$;
