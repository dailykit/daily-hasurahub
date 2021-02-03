CREATE OR REPLACE FUNCTION products."getOnlineStoreSRPProduct"(productid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    product record;
    temp jsonb;
    tempRec record;
    res jsonb;
    options jsonb[];
    option record;
BEGIN
    
    SELECT * FROM products."simpleRecipeProduct" WHERE id = productId INTO product;
    
    -- basic product details
    res := jsonb_build_object(
        'id', product.id,
        'name', product.name,
        'description', product.description,
        'default', product.default,
        'additionalText', product."additionalText",
        'tags', product.tags,
        'recommendations', product.recommendations,
        'assets', product.assets,
        'isPopupAllowed', product."isPopupAllowed",
        '__typename', 'products_simpleRecipeProduct'
    );
    
    -- recipe details
    SELECT * FROM "simpleRecipe"."simpleRecipe" WHERE id = product."simpleRecipeId" INTO tempRec;
    res := jsonb_set(res, '{simpleRecipe}', jsonb_build_object(
        'id', tempRec.id,
        'name', tempRec.name,
        'author', tempRec.author,
        'type', tempRec.type,
        'cuisine', tempRec.cuisine,
        'show', tempRec.show
    ), true);
    
    -- default cart item
    SELECT products."defaultSimpleRecipeProductCartItem"("simpleRecipeProduct".*) FROM products."simpleRecipeProduct" WHERE id = product.id INTO temp;
    res := jsonb_set(res, '{defaultCartItem}', temp, true);
    
    -- options
    FOR option IN SELECT * FROM products."simpleRecipeProductOption" WHERE "simpleRecipeProductId" = product.id AND "isActive" = true AND "isArchived" = false ORDER BY position DESC NULLS LAST LOOP
        
        -- basic option details
        temp := jsonb_build_object(
            'id', option.id,
            'price', option.price,
            'type', option.type,
            'simpleRecipeYieldId', option."simpleRecipeYieldId"
        );
        
        -- simple recipe yield
        SELECT * FROM "simpleRecipe"."simpleRecipeYield" WHERE id = option."simpleRecipeYieldId" INTO tempRec;
        temp := jsonb_set(temp, '{simpleRecipeYield}', jsonb_build_object('yield', tempRec.yield), true);
        
        -- modifier
        IF option."modifierId" IS NOT NULL THEN
            SELECT * FROM "onDemand".modifier WHERE id = option."modifierId" INTO tempRec;
            temp := jsonb_set(temp, '{modifier}', jsonb_build_object('id', tempRec.id, 'name', tempRec.name, 'data', tempRec.data), true);
        END IF;
        
        -- check if this option is default
        IF option.id = product.default THEN
            res := jsonb_set(res, '{defaultSimpleRecipeProductOption}', temp, true);
        END IF;
        
        options := options || temp;
        
    END LOOP;
    
    res := res || jsonb_build_object('simpleRecipeProductOptions', options);
        
    RETURN res;
END;
$function$;
