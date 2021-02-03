CREATE OR REPLACE FUNCTION products."getOnlineStoreIPProduct"(productid integer)
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
    
    SELECT * FROM products."inventoryProduct" WHERE id = productId INTO product;
        
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
        '__typename', 'products_inventoryProduct'
    );
    
    -- item
    IF product."sachetItemId" IS NOT NULL THEN
        SELECT * FROM inventory."sachetItem" WHERE id = product."sachetItemId" INTO tempRec;
        res := jsonb_set(res, '{item}', jsonb_build_object(
            'unitSize', tempRec."unitSize",
            'unit', tempRec.unit,
            'type', 'sachetItem'
        ), true);
    ELSE
        SELECT * FROM inventory."supplierItem" WHERE id = product."supplierItemId" INTO tempRec;
        res := jsonb_set(res, '{item}', jsonb_build_object(
            'unitSize', tempRec."unitSize",
            'unit', tempRec.unit,
            'type', 'supplierItem'
        ), true);
    END IF;
    
    -- default cart item
    SELECT products."defaultInventoryProductCartItem"("inventoryProduct".*) FROM products."inventoryProduct" WHERE id = product.id INTO temp;
    res := jsonb_set(res, '{defaultCartItem}', temp, true);
    
    -- options
    FOR option IN SELECT * FROM products."inventoryProductOption" WHERE "inventoryProductId" = product.id AND "isArchived" = false ORDER BY position DESC NULLS LAST LOOP
        
        -- basic option details
        temp := jsonb_build_object(
            'id', option.id,
            'price', option.price,
            'quantity', option.quantity,
            'label', option.label
        );
        
        -- modifier
        IF option."modifierId" IS NOT NULL THEN
            SELECT * FROM "onDemand".modifier WHERE id = option."modifierId" INTO tempRec;
            temp := jsonb_set(temp, '{modifier}', jsonb_build_object('id', tempRec.id, 'name', tempRec.name, 'data', tempRec.data), true);
        END IF;
        
        -- check if this option is default
        IF option.id = product.default THEN
            res := jsonb_set(res, '{defaultInventoryProductOption}', temp, true);
        END IF;
        
        options := options || temp;
        
    END LOOP;
    
    res := res || jsonb_build_object('inventoryProductOptions', options);
        
    RETURN res;
END;
$function$;
