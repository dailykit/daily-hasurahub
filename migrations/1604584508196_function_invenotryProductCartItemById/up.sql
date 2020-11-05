CREATE OR REPLACE FUNCTION products."inventoryProductCartItemById"("productId" integer, "optionId" integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    option jsonb;
    product products."inventoryProduct";
BEGIN
    SELECT * FROM products."inventoryProduct" WHERE id = "productId" INTO product ;
    SELECT json_build_object(
        'id', id,
        'price', CAST ("price"->0->>'value' AS numeric),
        'discount', CAST ("price"->0->>'discount' AS numeric)
    ) FROM "products"."inventoryProductOption" WHERE id = "optionId" into option;
    
    RETURN json_build_object(
        'id', product.id,
        'name', product.name,
        'type', 'inventoryProduct',
        'image', product."assets"->'images'->0,
        'option', option,
        'discount', option->'discount',
        'quantity', 1,
        'unitPrice', option->'price',
        'cartItemId', gen_random_uuid(),
        'totalPrice', option->'price',
        'specialInstructions', ''
    );
END
$function$;
