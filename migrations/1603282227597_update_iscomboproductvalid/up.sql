CREATE OR REPLACE FUNCTION products.iscomboproductvalid(product products."comboProduct")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    res json;
    temp int;
BEGIN
    SELECT COUNT(*) FROM "products"."comboProductComponent" where "comboProductComponent"."comboProductId" = product.id into temp;
    IF temp < 2
        THEN res := json_build_object('status', false, 'error', 'Atleast 2 options required');
    ELSE
        res := json_build_object('status', true, 'error', '');
    END IF;
    IF (res->>'status')::boolean = false AND product."isPublished" = true
        THEN PERFORM products."unpublishProduct"('comboProduct', product.id);
    END IF;
    RETURN res;
END
$function$;
