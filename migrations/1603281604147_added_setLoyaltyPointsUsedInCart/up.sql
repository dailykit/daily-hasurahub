CREATE OR REPLACE FUNCTION crm."setLoyaltyPointsUsedInCart"(cartid integer, points integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE crm."orderCart"
    SET "loyaltyPointsUsed" = points
    WHERE id = cartId;
END
$function$;
