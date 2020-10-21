CREATE OR REPLACE FUNCTION crm.totalprice(ordercart crm."orderCart")
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
   totalPrice numeric;
   tax numeric;
   itemTotal numeric;
   deliveryPrice numeric;
   discount numeric;
   rate numeric;
   loyaltyPointsAmount numeric := 0;
BEGIN
    SELECT crm.itemtotal(ordercart.*) into itemTotal;
    SELECT crm.deliveryprice(ordercart.*) into deliveryPrice;
    SELECT crm.tax(ordercart.*) into tax;
    SELECT crm.discount(ordercart.*) into discount;
    IF ordercart."loyaltyPointsUsed" > 0 THEN
        SELECT crm."getLoyaltyPointsConversionRate"(ordercart."brandId") INTO rate;
        loyaltyPointsAmount := ROUND(rate * ordercart."loyaltyPointsUsed", 2);
    END IF;
    totalPrice := ROUND(itemTotal + deliveryPrice + ordercart.tip - COALESCE(ordercart."walletAmountUsed", 0) - loyaltyPointsAmount  + tax - discount, 2);
    RETURN totalPrice;
END
$function$;
