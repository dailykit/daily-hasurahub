CREATE OR REPLACE FUNCTION products."getInventoryProductRichResult"(product products."inventoryProduct")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    res jsonb := '{ "@context": "https://schema.org/", "@type": "Product" }';
    p jsonb;
BEGIN
    res := res || jsonb_build_object('name', product.name, 'image', product.assets->'images', 'keywords', product.name);
    IF product.description IS NOT NULL THEN
        res := res || jsonb_build_object('description', product.description);
    END IF;
    SELECT price FROM products."inventoryProductOption" WHERE id = product."default" INTO p;
    res := res || jsonb_build_object('offers', jsonb_build_object('@type', 'Offer', 'priceCurrency', 'USD', 'price', (p->0->>'value')::numeric));
    return res;
END;
$function$;
