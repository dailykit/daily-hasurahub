CREATE OR REPLACE FUNCTION products."getOnlineStoreCOMPProduct"(productid integer)
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
    
    SELECT * FROM products."comboProduct" WHERE id = productId INTO product;
        
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
        '__typename', 'products_comboProduct'
    );
    
    -- default cart item
    SELECT products."defaultComboProductCartItem"("comboProduct".*) FROM products."comboProduct" WHERE id = product.id INTO temp;
    res := jsonb_set(res, '{defaultCartItem}', temp, true);
    
    -- options
    FOR option IN SELECT * FROM products."comboProductComponent" WHERE "comboProductId" = product.id AND "isArchived" = false ORDER BY position DESC NULLS LAST LOOP
        
        --- get underlying produduct with new prices + filtered options
        IF option."inventoryProductId" IS NOT NULL AND option.options IS NOT NULL AND JSONB_ARRAY_LENGTH(option.options) > 0 THEN
            SELECT products."getProductBaseProductWithPriceOverwrite"(option."inventoryProductId", 'inventoryProduct', option.options) INTO temp;
            temp := jsonb_build_object('inventoryProduct', temp, 'id', option.id, 'label', option.label);
        ELSIF option."simpleRecipeProductId" IS NOT NULL AND option.options IS NOT NULL AND JSONB_ARRAY_LENGTH(option.options) > 0 THEN 
            SELECT products."getProductBaseProductWithPriceOverwrite"(option."simpleRecipeProductId", 'simpleRecipeProduct', option.options) INTO temp;
            temp := jsonb_build_object('simpleRecipeProduct', temp, 'id', option.id, 'label', option.label);
        ELSIF option."customizableProductId" IS NOT NULL THEN 
            SELECT products."getOnlineStoreCUSPProduct"(option."customizableProductId") INTO temp;
            temp := jsonb_build_object('customizableProduct', temp, 'id', option.id, 'label', option.label);
        END IF;
        
        options := options || temp;
        
    END LOOP;
    
    res := res || jsonb_build_object('comboProductComponents', COALESCE(options, '{}'));
        
    RETURN res;
END;
$function$;
