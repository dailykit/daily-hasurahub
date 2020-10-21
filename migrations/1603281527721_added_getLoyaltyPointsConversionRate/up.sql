CREATE OR REPLACE FUNCTION crm."getLoyaltyPointsConversionRate"(brandid integer)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    setting record;
    temp record;
BEGIN
        SELECT * FROM brands."storeSetting" WHERE "type" = 'rewards' and "identifier" = 'Loyalty Points Usage' INTO setting;
        SELECT * FROM brands."brand_storeSetting" WHERE "brandId" = brandId AND "storeSettingId" = setting.id INTO temp;
        IF temp IS NOT NULL THEN
            setting := temp;
        END IF;
        RETURN ROUND((setting."value"->>'conversionRate')::numeric, 2);
    RETURN NULL;
END
$function$;
