CREATE OR REPLACE FUNCTION crm."deductLoyaltyPointsPostOrder"()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    cart record;
    amount numeric;
    loyaltyPointId int;
    setting record;
    temp record;
    rate numeric;
BEGIN
    SELECT * FROM crm."orderCart" WHERE id = NEW."cartId" INTO cart;
    SELECT id FROM crm."loyaltyPoint" WHERE "keycloakId" = NEW."keycloakId" AND "brandId" = NEW."brandId" INTO loyaltyPointId; 
    IF cart."loyaltyPointsUsed" > 0 THEN
        SELECT crm."getLoyaltyPointsConversionRate"(NEW."brandId") INTO rate;
        amount := ROUND((cart."loyaltyPointsUsed" * rate), 2);
        INSERT INTO crm."loyaltyPointTransaction"("loyaltyPointId", "points", "orderCartId", "type", "amountRedeemed")
        VALUES (loyaltyPointId, cart."loyaltyPointsUsed", cart.id, 'DEBIT', amount);
    END IF;
    RETURN NULL;
END
$function$;
