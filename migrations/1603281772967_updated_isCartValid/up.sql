CREATE OR REPLACE FUNCTION crm.iscartvalid(ordercart crm."orderCart")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    totalPrice numeric := 0;
BEGIN
    SELECT crm.totalPrice(ordercart.*) INTO totalPrice;
    IF JSONB_ARRAY_LENGTH(ordercart."cartInfo"->'products') = 0
        THEN RETURN json_build_object('status', false, 'error', 'No items in cart!');
    ELSIF ordercart."customerInfo" IS NULL OR ordercart."customerInfo"->>'customerFirstName' IS NULL 
        THEN RETURN json_build_object('status', false, 'error', 'Basic customer details missing!');
    ELSIF ordercart."paymentMethodId" IS NULL OR ordercart."stripeCustomerId" IS NULL
        THEN RETURN json_build_object('status', false, 'error', 'No payment method selected!');
    ELSIF ordercart."fulfillmentInfo" IS NULL
        THEN RETURN json_build_object('status', false, 'error', 'No fulfillment mode selected!');
    ELSIF ordercart."address" IS NULL AND ordercart."fulfillmentInfo"::json->>'type' LIKE '%DELIVERY' 
        THEN RETURN json_build_object('status', false, 'error', 'No address selected for delivery!');
    ELSIF totalPrice > 0 AND totalPrice <= 0.5
        THEN RETURN json_build_object('status', false, 'error', 'Transaction amount should be greater than $0.5!');
    ELSE
        RETURN json_build_object('status', true, 'error', '');
    END IF;
END
$function$;
