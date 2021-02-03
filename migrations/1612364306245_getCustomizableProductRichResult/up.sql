CREATE OR REPLACE FUNCTION products."getCustomizableProductRichResult"(product products."customizableProduct")
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    res jsonb := '{ "@context": "https://schema.org/", "@type": "Product" }';
BEGIN
    res := res || jsonb_build_object('name', product.name, 'image', product.assets->'images', 'keywords', product.name);
    IF product.description IS NOT NULL THEN
        res := res || jsonb_build_object('description', product.description);
    END IF;
    res := res || jsonb_build_object('offers', jsonb_build_object('@type', 'Offer', 'priceCurrency', 'USD', 'price', (product.price->>'value')::numeric));
    return res;
END;
$function$;
