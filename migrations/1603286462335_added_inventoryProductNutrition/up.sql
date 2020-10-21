CREATE OR REPLACE FUNCTION products."inventoryProductNutrition"(product products."inventoryProduct")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    data jsonb;
BEGIN
    IF product."supplierItemId" IS NOT NULL THEN
        SELECT "nutritionInfo" FROM inventory."bulkItem" WHERE id = (SELECT "bulkItemAsShippedId" FROM inventory."supplierItem" WHERE id = product."supplierItemId") INTO data;
    ELSE
        SELECT "nutritionInfo" FROM inventory."bulkItem" WHERE id = (SELECT "bulkItemId" FROM inventory."sachetItem" WHERE id = product."sachetItemId") INTO data;
    END IF;
    RETURN data;
END;
$function$;
