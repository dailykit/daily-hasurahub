CREATE OR REPLACE FUNCTION products."productCartItemById"(optionid integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    counter int;
    items jsonb[] := '{}';
    option products."productOption";
    product products."product";
BEGIN
    SELECT * INTO option FROM products."productOption" WHERE id = optionId;
    SELECT * FROM products.product WHERE id = option."productId" INTO product;
    
    counter := option.quantity;
    
    IF option."simpleRecipeYieldId" IS NOT NULL THEN 
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    
    RETURN json_build_object(
        'productId', product.id,
        'childs', jsonb_build_object(
            'data', json_build_array(
                json_build_object (
                    'productOptionId', option.id,
                    'unitPrice', 0,
                    'childs', json_build_object(
                        'data', items
                    )
                )
            )
        )
    );
END
$function$;
