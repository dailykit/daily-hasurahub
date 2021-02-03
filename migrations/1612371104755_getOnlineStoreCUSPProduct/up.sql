CREATE OR REPLACE FUNCTION products."getOnlineStoreCUSPProduct"(productid integer)
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
    
    SELECT * FROM products."customizableProduct" WHERE id = productId INTO product;
        
    -- basic product details
    res := jsonb_build_object(
        'id', product.id,
        'name', product.name,
        'description', product.description,
        'additionalText', product."additionalText",
        'tags', product.tags,
        'assets', product.assets,
        'isPopupAllowed', product."isPopupAllowed",
        'price', product.price,
        '__typename', 'products_customizableProduct'
    );
    
    -- default cart item
    SELECT products."defaultCustomizableProductCartItem"("customizableProduct".*) FROM products."customizableProduct" WHERE id = product.id INTO temp;
    res := jsonb_set(res, '{defaultCartItem}', temp, true);
    
    -- options
    FOR option IN SELECT * FROM products."customizableProductOption" WHERE "customizableProductId" = product.id AND "isArchived" = false ORDER BY position DESC NULLS LAST LOOP
        
        --- get underlying produduct with new prices + filtered options
        IF option.options IS NOT NULL AND JSONB_ARRAY_LENGTH(option.options) > 0 THEN
            IF option."inventoryProductId" IS NOT NULL THEN
                SELECT products."getProductBaseProductWithPriceOverwrite"(option."inventoryProductId", 'inventoryProduct', option.options) INTO temp;
                temp := jsonb_build_object('inventoryProduct', temp, 'id', option.id);
            ELSE
                SELECT products."getProductBaseProductWithPriceOverwrite"(option."simpleRecipeProductId", 'simpleRecipeProduct', option.options) INTO temp;
                temp := jsonb_build_object('simpleRecipeProduct', temp, 'id', option.id);
            END IF;
        
            IF option.id = product.default THEN
                res := jsonb_set(res, '{defaultCustomizableProductOption}', temp, true);
            END IF;
        
            options := options || temp;
        END IF;
        
    END LOOP;
    
    res := res || jsonb_build_object('customizableProductOptions', COALESCE(options, '{}'));
        
    RETURN res;
END;
$function$;
