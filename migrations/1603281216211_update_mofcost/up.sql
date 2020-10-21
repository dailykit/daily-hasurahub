CREATE OR REPLACE FUNCTION ingredient."MOFCost"(mofid integer)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    mof record;
    bulkItemId int;
    supplierItemId int;
    supplierItem record;
    costs jsonb;
BEGIN
    SELECT * FROM ingredient."modeOfFulfillment" WHERE id = mofId into mof;
    IF mof."bulkItemId" IS NOT NULL
        THEN SELECT mof."bulkItemId" into bulkItemId;
    ELSE
        SELECT bulkItemId FROM inventory."sachetItem" WHERE id = mof."sachetItemId" into bulkItemId;
    END IF;
    SELECT "supplierItemId" FROM inventory."bulkItem" WHERE id = bulkItemId into supplierItemId;
    SELECT * FROM inventory."supplierItem" WHERE id = supplierItemId into supplierItem;
    IF supplierItem.prices IS NULL OR supplierItem.prices->0->'unitPrice'->>'value' = ''
        THEN RETURN 0;
    ELSE
        RETURN (supplierItem.prices->0->'unitPrice'->>'value')::numeric/supplierItem."unitSize";
    END IF;
END
$function$;
