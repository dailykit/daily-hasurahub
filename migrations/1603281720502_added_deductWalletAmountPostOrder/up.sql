CREATE OR REPLACE FUNCTION crm."deductWalletAmountPostOrder"()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    cart record;
    walletId int;
BEGIN
    SELECT * FROM crm."orderCart" WHERE id = NEW."cartId" INTO cart;
    SELECT id FROM crm."wallet" WHERE "keycloakId" = NEW."keycloakId" AND "brandId" = NEW."brandId" INTO walletId; 
    IF cart."walletAmountUsed" > 0 THEN
        INSERT INTO crm."walletTransaction"("walletId", "amount", "orderCartId", "type")
        VALUES (walletId, cart."walletAmountUsed", cart.id, 'DEBIT');
    END IF;
    RETURN NULL;
END
$function$;
