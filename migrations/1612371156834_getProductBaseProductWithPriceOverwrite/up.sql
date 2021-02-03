CREATE OR REPLACE FUNCTION products."getProductBaseProductWithPriceOverwrite"(productid integer, producttype text, filteredoptions jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    baseProduct jsonb;
    updatedOptions jsonb[];
    updatedOption jsonb;
    op jsonb;
    option jsonb;
    res jsonb;
    k text;
    k2 text;
    defaultUpdated boolean := false;
BEGIN
    IF producttype = 'inventoryProduct' THEN
        SELECT products."getOnlineStoreIPProduct"(productid) INTO baseProduct;
        k2 := 'defaultInventoryProductOption';
    ELSE
        SELECT products."getOnlineStoreSRPProduct"(productid) INTO baseProduct;
        k2 := 'defaultSimpleRecipeProductOption';
    END IF;
    k := producttype || 'Options';
    -- overwrite options
    FOR op IN SELECT * FROM JSONB_ARRAY_ELEMENTS(filteredoptions) LOOP
        FOR option IN SELECT * FROM JSONB_ARRAY_ELEMENTS(baseProduct->k) LOOP
            IF (option->>'id')::int = (op->>'optionId')::int THEN
                updatedOption := option || jsonb_build_object('price', jsonb_build_array(jsonb_build_object('value', (op->>'price')::numeric, 'discount', (op->'discount')::numeric)));
                updatedOptions := updatedOptions || updatedOption;
                -- overwrite default
                IF (option->>'id')::int = (baseProduct->k2->>'id')::int THEN
                    baseProduct := baseProduct || jsonb_build_object(k2, updatedOption);
                    defaultUpdated := true;
                END IF;
            END IF;
        END LOOP;
    END LOOP;
    
    -- check if default was updated
    IF defaultUpdated = false THEN
        baseProduct := baseProduct || jsonb_build_object(k2, updatedOptions[0]);
    END IF;
    
    res := baseProduct || jsonb_build_object(k, updatedOptions);
    RETURN res;
END;
$function$;
