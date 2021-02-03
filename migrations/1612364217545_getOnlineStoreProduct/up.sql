CREATE OR REPLACE FUNCTION "onDemand"."getOnlineStoreProduct"(productid integer, producttype text)
 RETURNS SETOF "onDemand".menu
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    res jsonb;
BEGIN
  IF producttype = 'simpleRecipeProduct' THEN
        SELECT products."getOnlineStoreSRPProduct"(productid) INTO res;
    ELSIF producttype = 'inventoryProduct' THEN
        SELECT products."getOnlineStoreIPProduct"(productid) INTO res;
    ELSIF producttype = 'customizableProduct' THEN
        SELECT products."getOnlineStoreCUSPProduct"(productid) INTO res;
    ELSE
        SELECT products."getOnlineStoreCOMPProduct"(productid) INTO res;
    END IF;
    RETURN QUERY SELECT 1 AS id, res AS data;
END;
$function$;
