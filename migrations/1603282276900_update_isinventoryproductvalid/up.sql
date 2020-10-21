CREATE OR REPLACE FUNCTION products.isinventoryproductvalid(product products."inventoryProduct")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    res json;
BEGIN
    IF product."supplierItemId" IS NULL AND product."sachetItemId" IS NULL
        THEN res := json_build_object('status', false, 'error', 'Item not provided');
    ELSIF product."default" IS NULL
        THEN res := json_build_object('status', false, 'error', 'Default option not provided');
    ELSE
        res := json_build_object('status', true, 'error', '');
    END IF;
    IF (res->>'status')::boolean = false AND product."isPublished" = true
        THEN PERFORM products."unpublishProduct"('inventoryProduct', product.id);
    END IF;
    RETURN res;
END
$function$;
