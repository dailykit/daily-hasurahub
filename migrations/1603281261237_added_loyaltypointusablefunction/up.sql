CREATE OR REPLACE FUNCTION crm."loyaltyPointsUsable"(ordercart crm."orderCart")
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
   setting record;
   temp record;
   itemTotal numeric;
   deliveryPrice numeric;
   tax numeric;
   discount numeric;
   totalPrice numeric;
   amount numeric;
   rate numeric;
   pointsUsable int := 0;
   balance int;
BEGIN
    SELECT * FROM brands."storeSetting" WHERE "identifier" = 'Loyalty Points Usage' AND "type" = 'rewards' INTO setting;
    SELECT * FROM brands."brand_storeSetting" WHERE "storeSettingId" = setting.id AND "brandId" = ordercart."brandId" INTO temp;
    IF temp IS NOT NULL THEN
        setting := temp;
    END IF;
    IF setting IS NULL THEN
        RETURN pointsUsable;
    END IF;
    SELECT crm.itemtotal(ordercart.*) into itemTotal;
    SELECT crm.deliveryprice(ordercart.*) into deliveryPrice;
    SELECT crm.tax(ordercart.*) into tax;
    SELECT crm.discount(ordercart.*) into discount;
    totalPrice := ROUND(itemTotal + deliveryPrice + ordercart.tip  + tax - ordercart."walletAmountUsed" - discount, 2);
    amount := ROUND(totalPrice * ((setting.value->>'percentage')::float / 100));
    IF amount > (setting.value->>'max')::int THEN
        amount := (setting.value->>'max')::int;
    END IF;
    SELECT crm."getLoyaltyPointsConversionRate"(ordercart."brandId") INTO rate;
    pointsUsable = ROUND(amount / rate);
    SELECT points FROM crm."loyaltyPoint" WHERE "keycloakId" = ordercart."customerKeycloakId" AND "brandId" = ordercart."brandId" INTO balance;
    IF pointsUsable > balance THEN
        pointsUsable := balance;
    END IF;
    -- if usable changes after cart update, then update used points
    IF ordercart."loyaltyPointsUsed" > pointsUsable THEN
        PERFORM crm."setLoyaltyPointsUsedInCart"(ordercart.id, pointsUsable);
    END IF;
    RETURN pointsUsable;
END;
$function$;
