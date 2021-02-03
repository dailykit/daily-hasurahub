CREATE OR REPLACE FUNCTION "onDemand"."getMenuV2"(params jsonb)
 RETURNS SETOF "onDemand".menu
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    colId int;
    menu jsonb[] := '{}';
    object jsonb;
    isValid jsonb;
    category jsonb;
    productCategory record;
    rec record;
    cleanMenu jsonb[] := '{}'; -- without duplicates
    cleanCategory jsonb; -- without duplicates
    categoriesIncluded text[];
    productsIncluded text[];
    updatedProducts jsonb[] := '{}';
    product jsonb;
    pos int := 0;
BEGIN

    -- generating menu data from collections
    FOR colId IN SELECT "collectionId" FROM "onDemand"."brand_collection" WHERE "brandId" = (params->>'brandId')::int AND "isActive" = true LOOP
        SELECT "onDemand"."isCollectionValid"(colId, params) INTO isValid;
        IF (isValid->'status')::boolean = true THEN
            FOR productCategory IN SELECT * FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId ORDER BY position DESC NULLS LAST LOOP
                category := jsonb_build_object(
                    'name', productCategory."productCategoryName",
                    'products', jsonb_build_array()
                );
                FOR rec IN SELECT * FROM "onDemand"."collection_productCategory_product" WHERE "collection_productCategoryId" = productCategory.id ORDER BY position DESC NULLS LAST LOOP
                    IF rec."simpleRecipeProductId" IS NOT NULL THEN
                        SELECT products."getOnlineStoreSRPProduct"(rec."simpleRecipeProductId") INTO object;
                        category := jsonb_set(category, '{products}', category->'products' || object, false);
                    ELSIF rec."inventoryProductId" IS NOT NULL THEN
                        SELECT products."getOnlineStoreIPProduct"(rec."inventoryProductId") INTO object;
                        category := jsonb_set(category, '{products}', category->'products' || object, false);
                    ELSIF rec."customizableProductId" IS NOT NULL THEN
                        SELECT products."getOnlineStoreCUSPProduct"(rec."customizableProductId") INTO object;
                        category := jsonb_set(category, '{products}', category->'products' || object, false);
                    ELSIF rec."comboProductId" IS NOT NULL THEN
                        SELECT products."getOnlineStoreCOMPProduct"(rec."comboProductId") INTO object;
                        category := jsonb_set(category, '{products}', category->'products' || object, false);
                    ELSE
                        CONTINUE;
                    END IF;
                END LOOP;
                menu := menu || category;
            END LOOP;
        ELSE
            CONTINUE;
        END IF;
    END LOOP;
    
    -- merge duplicate categories and remove duplicate products
    FOREACH category IN ARRAY(menu) LOOP
        pos := ARRAY_POSITION(categoriesIncluded, category->>'name');
        IF pos >= 0 THEN
            updatedProducts := '{}';
            productsIncluded := '{}';
            FOR product IN SELECT * FROM JSONB_ARRAY_ELEMENTS(cleanMenu[pos]->'products') LOOP
                updatedProducts := updatedProducts || product;
                productsIncluded := productsIncluded || (product->>'name')::text; -- wil remove same products under same category in different collections
            END LOOP;
            FOR product IN SELECT * FROM JSONB_ARRAY_ELEMENTS(category->'products') LOOP
                IF ARRAY_POSITION(productsIncluded, product->>'name') >= 0 THEN
                    CONTINUE;
                ELSE
                   updatedProducts := updatedProducts || product;
                   productsIncluded := productsIncluded || (product->>'name')::text; -- will remove same products under same category in same collection
                END IF;
            END LOOP;
            cleanMenu[pos] := jsonb_build_object('name', category->>'name', 'products', updatedProducts);
        ELSE
            cleanMenu := cleanMenu || category;
            categoriesIncluded := categoriesIncluded || (category->>'name')::text;
        END IF;
    END LOOP;
    
    RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', cleanMenu) AS data;
END;
$function$;
