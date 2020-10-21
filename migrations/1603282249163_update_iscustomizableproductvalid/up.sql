CREATE OR REPLACE FUNCTION products.iscustomizableproductvalid(product products."customizableProduct")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    res json;
    temp json;
BEGIN
    SELECT id FROM "products"."customizableProductOption" where "customizableProductOption"."customizableProductId" = product.id LIMIT 1 into temp;
    IF temp IS NULL
        THEN res := json_build_object('status', false, 'error', 'No options provided');
    ELSIF product."default" IS NULL
        THEN res := json_build_object('status', false, 'error', 'Default option not provided');
    ELSE
        res := json_build_object('status', true, 'error', '');
    END IF;
    IF (res->>'status')::boolean = false AND product."isPublished" = true
        THEN PERFORM products."unpublishProduct"('customizableProduct', product.id);
    END IF;
    RETURN res;
END
$function$;
