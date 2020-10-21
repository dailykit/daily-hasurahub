CREATE OR REPLACE FUNCTION crm."walletAmountUsable"(ordercart crm."orderCart")
 RETURNS numeric
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
   rate numeric;
   pointsAmount numeric := 0;
   amountUsable numeric := 0;
   balance numeric;
BEGIN
    SELECT * FROM brands."storeSetting" WHERE "identifier" = 'Loyalty Points Usage' AND "type" = 'rewards' INTO setting;
    SELECT * FROM brands."brand_storeSetting" WHERE "storeSettingId" = setting.id AND "brandId" = ordercart."brandId" INTO temp;
    IF temp IS NOT NULL THEN
        setting := temp;
    END IF;
    SELECT crm.itemtotal(ordercart.*) into itemTotal;
    SELECT crm.deliveryprice(ordercart.*) into deliveryPrice;
    SELECT crm.tax(ordercart.*) into tax;
    SELECT crm.discount(ordercart.*) into discount;
    totalPrice := ROUND(itemTotal + deliveryPrice + ordercart.tip  + tax - discount, 2);
    amountUsable := totalPrice;
    -- if loyalty points are used
    IF ordercart."loyaltyPointsUsed" > 0 THEN
        SELECT crm."getLoyaltyPointsConversionRate"(ordercart."brandId") INTO rate;
        pointsAmount := rate * ordercart."loyaltyPointsUsed";
        amountUsable := amountUsable - pointsAmount;
    END IF;
    SELECT amount FROM crm."wallet" WHERE "keycloakId" = ordercart."customerKeycloakId" AND "brandId" = ordercart."brandId" INTO balance;
    IF amountUsable > balance THEN
        amountUsable := balance;
    END IF;
    -- if usable changes after cart update, then update used amount
    IF ordercart."walletAmountUsed" > amountUsable THEN
        PERFORM crm."setWalletAmountUsedInCart"(ordercart.id, amountUsable);
    END IF;
    RETURN amountUsable;
END;
$function$;
