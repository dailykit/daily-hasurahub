CREATE OR REPLACE FUNCTION products."isProductValid"(product products.product)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    component record;
    isValid boolean := true;
    message text := '';
    counter int := 0;
BEGIN   
    RETURN jsonb_build_object('status', isValid, 'error', message);
END
$function$;
