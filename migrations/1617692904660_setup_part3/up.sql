CREATE TABLE products."productOption" (
    id integer DEFAULT public.defaultid('products'::text, 'productOption'::text, 'id'::text) NOT NULL,
    "productId" integer NOT NULL,
    label text DEFAULT 'Basic'::text NOT NULL,
    "modifierId" integer,
    "operationConfigId" integer,
    "simpleRecipeYieldId" integer,
    "supplierItemId" integer,
    "sachetItemId" integer,
    "position" numeric,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    price numeric DEFAULT 0 NOT NULL,
    discount numeric DEFAULT 0 NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    type text,
    "isArchived" boolean DEFAULT false NOT NULL,
    "inventoryProductBundleId" integer
);

CREATE FUNCTION products."productOptionFullName"(option products."productOption") RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    productName text;
BEGIN
    SELECT name FROM products.product WHERE id = option."productId" INTO productName;
    RETURN option.label || ' - ' || productName;
END;
$$;
CREATE FUNCTION products.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION products."unpublishProduct"(producttype text, productid integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    query text;
BEGIN
    query := 'UPDATE products.' || '"' || productType || '"' || ' SET "isPublished" = false WHERE id = ' || productId;
    EXECUTE query;
END
$$;
CREATE FUNCTION public.call(text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$ 
DECLARE
    res jsonb;
BEGIN 
    EXECUTE $1 INTO res; 
    RETURN res; 
END;
$_$;
CREATE FUNCTION public.exec(text) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$ 
DECLARE
    res boolean;
BEGIN 
    EXECUTE $1 INTO res; 
    RETURN res; 
END;
$_$;
CREATE FUNCTION public.json_to_array(json) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $_$
SELECT coalesce(array_agg(x),
                CASE
                    WHEN $1 is null THEN null
                    ELSE ARRAY[]::text[]
                END)
FROM json_array_elements_text($1) t(x); $_$;
CREATE FUNCTION public.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION rules."assertFact"(condition jsonb, params jsonb) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    x jsonb;
    factValue jsonb;
    values jsonb;
    res boolean;
BEGIN
    x := condition || params;
   SELECT rules."getFactValue"(condition->>'fact', x) INTO factValue;
   SELECT jsonb_build_object('condition', condition->'value', 'fact', factValue->'value') INTO values;
   SELECT rules."runWithOperator"(condition->>'operator', values) INTO res;
   RETURN res;
END;
$$;
CREATE FUNCTION rules."budgetFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    typeof text ;
    total numeric := 0;
    campaignRecord record;
    campIds integer array DEFAULT '{}';
    queryParams jsonb default '{}'::jsonb ;
    endDate timestamp without time zone;
    startDate timestamp without time zone ;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
    query text :='';
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'budget', 'fact', 'budget', 'title', 'Budget', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ comboProducts { id title: name } }" }'::json, 'argument','couponId', 'operators', operators);
    END IF;
    query := query || 'SELECT ' || (params->>'type')::text || '(' || '"'|| (params->>'rewardType')::text || '"' || ')' || ' FROM crm."rewardHistory" WHERE ';
    IF (params->'perCustomer')::boolean = true THEN
        query := query || '"keycloakId" = ' || '''' || (params->>'keycloakId')::text|| '''' || ' AND ';
    END IF;
    IF params->>'coverage' = 'Only This' THEN
        IF params->>'couponId' IS NOT NULL THEN
            query := query || ' "couponId" = ' || (params->>'couponId')::text ||'AND';
        ELSIF params->>'campaignId' IS NOT NULL THEN
            query := query || ' "campaignId" = ' || (params->>'campaignId')::text||'AND';
        ELSE
            query := query;
        END IF;
     ELSEIF params->>'coverage'='Sign Up' OR params->>'coverage'='Post Order' OR params->>'coverage'='Referral' THEN
        FOR campaignRecord IN
            SELECT * FROM crm."campaign" WHERE "type" = (params->>'coverage')::text
        LOOP
            campIds := campIds || (campaignRecord."id")::int;
        END LOOP;
            query := query || ' "campaignId" IN ' || '(' || array_to_string(campIds, ',') || ')'  ||'AND';
    ELSEIF params->>'coverage' = 'coupons' THEN
        query := query || ' "couponId" IS NOT NULL AND';
    ELSEIF params->>'coverage' = 'campaigns' THEN
        query := query || ' "campaignId" IS NOT NULL AND';
    ELSE
        query := query;
    END IF;
    IF (params->>'duration')::interval IS NOT NULL THEN
        endDate := now()::timestamp without time zone;
        startDate := endDate - (params->>'duration')::interval;
        query := query || ' "created_at" > ' || '''' || startDate || '''' || 'AND "created_at" < ' || '''' || endDate::timestamp without time zone ||'''' ;
    ELSE
        query :=query;
    END IF;
    EXECUTE query INTO total;
    RETURN jsonb_build_object((params->>'type')::text, total, 'query', query);
END;
$$;
CREATE TABLE rules.facts (
    id integer DEFAULT public.defaultid('rules'::text, 'facts'::text, 'id'::text) NOT NULL,
    query text
);
CREATE FUNCTION rules."cartComboProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartComboProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartComboProductComponent"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartComboProductComponentFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartComboProductComponentFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartProduct" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartComboProductComponent', 'fact', 'cartComboProductComponent', 'title', 'Cart Contains Combo Product Component', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  comboProductComponents { id title: fullName } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartProduct"."productId" into productType;
            IF productType = 'combo'
             THEN SELECT "comboProductComponentId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartComboProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartComboProduct', 'fact', 'cartComboProduct', 'title', 'Cart Contains Combo Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"combo\"}}) { id title: name } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'combo'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartContainsAddOnProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartContainsAddOnProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartContainsAddOnProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    addedAddOnProductsCount int;
    operators text[] := ARRAY['equal', 'notEqual'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('fact', 'cartContainsAddOnProducts', 'title', 'Cart Contains AddOn Products','value', '{ "type" : "text" }'::json,'argument','cartId', 'operators', operators);
    ELSE
     Select COUNT(*) INTO addedAddOnProductsCount FROM "order"."cartItem" WHERE "cartId" = (params->>'cartId')::integer AND "isAddOn" = true AND "parentCartItemId" IS NULL;
    if addedAddOnProductsCount > 0 then
    RETURN jsonb_build_object('value', 'true', 'valueType','boolean','argument','cartid');
       else RETURN jsonb_build_object('value', 'false', 'valueType','boolean','argument','cartid');
       end if;
    END IF;
END;
$$;
CREATE FUNCTION rules."cartCustomizableProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartCustomizableProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartCustomizableProductComponent"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartCustomizableProductComponentFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartCustomizableProductComponentFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartProduct" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartCustomizableProductComponent', 'fact', 'cartCustomizableProductComponent', 'title', 'Cart Contains Customizable Product Component', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  customizableProductComponents { id title: fullName } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartProduct"."productId" into productType;
            IF productType = 'combo'
             THEN SELECT "CustomizableProductComponentId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartCustomizableProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartCustomizableProduct', 'fact', 'cartCustomizableProduct', 'title', 'Cart Contains Customizable Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"customizable\"}}) { id title: name } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'customizable'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartInventoryProductOption"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartInventoryProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;



CREATE FUNCTION rules."cartInventoryProductOptionFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartInventoryProductOption', 'fact', 'cartInventoryProductOption', 'title', 'Cart Contains Inventory Product Option', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"inventory\"}}) { id, title: fullName } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'inventory' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productOptionIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartItemTotal"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartItemTotalFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartItemTotalFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    total numeric;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF (params->>'read')::boolean = true
        THEN RETURN json_build_object('id', 'cartItemTotal', 'fact', 'cartItemTotal', 'title', 'Cart Item Total', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT COALESCE((SELECT SUM("unitPrice") FROM "order"."cartItem" WHERE "cartId" = (params->>'cartId')::integer), 0) INTO total;
        RETURN json_build_object('value', total, 'valueType','numeric','arguments','cartId');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartMealKitProductOption"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartMealKitProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartMealKitProductOptionFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartMealKitProductOption', 'fact', 'cartMealKitProductOption', 'title', 'Cart Contains Meal Kit Product Option', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"mealKit\"}}) { id, title: fullName } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'mealKit' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productOptionIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartReadyToEatProductOption"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartReadyToEatProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartReadyToEatProductOptionFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartReadyToEatProductOption', 'fact', 'cartReadyToEatProductOption', 'title', 'Cart Contains Ready to Eat Product Option', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"readyToEat\"}}) { id, title: fullName } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'readyToEat' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productOptionIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartSimpleProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartSimpleProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartSimpleProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartSimpleProduct', 'fact', 'cartSimpleProduct', 'title', 'Cart Contains Simple Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"simple\"}}) { id title: name } }" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'simple'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN jsonb_build_object('value', productIdArray, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartSubscriptionItemCount"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartSubscriptionItemCountFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartSubscriptionItemCountFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    subscriptionItemCount int;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('fact', 'cartSubscriptionItemCount', 'title', 'Cart Subscription Item Count','value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        select "subscriptionItemCount" into subscriptionItemCount from "subscription"."view_subscription" 
        where id = (select "subscriptionId" from "subscription"."subscriptionOccurence" 
        where id = (select "subscriptionOccurenceId" from "order"."cart" where id = (params->>'cartId')::integer));
        RETURN jsonb_build_object('value', subscriptionItemCount, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartSubscriptionServingSize"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartSubscriptionServingSizeFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartSubscriptionServingSizeFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    subscriptionServingSize int;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('fact', 'cartSubscriptionServingSize', 'title', 'Subscription Serving Size','value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        select "subscriptionServingSize" into subscriptionServingSize from "subscription"."view_subscription" 
        where id = (select "subscriptionId" from "subscription"."subscriptionOccurence" 
        where id = (select "subscriptionOccurenceId" from "order"."cart" where id = (params->>'cartId')::integer));
        RETURN jsonb_build_object('value', subscriptionServingSize, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."cartSubscriptionTitle"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartSubscriptionTitleFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."cartSubscriptionTitleFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    subscriptionTitle text;
    operators text[] := ARRAY['contains', 'doesNotContain', 'equal', 'notEqual'];
BEGIN
    IF (params->>'read')::boolean = true THEN
        RETURN jsonb_build_object('id', 'cartSubscriptionTitle', 'fact', 'cartSubscriptionTitle', 'title', 'Subscription Title', 'value', '{ "type" : "text" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        select "title" into subscriptionTitle from "subscription"."view_subscription" 
        where id = (select "subscriptionId" from "subscription"."subscriptionOccurence" 
        where id = (select "subscriptionOccurenceId" from "order"."cart" where id = (params->>'cartId')::integer));
        RETURN jsonb_build_object('value', subscriptionTitle, 'valueType','text','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."checkAllConditions"(conditionarray jsonb, params jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    condition jsonb;
    res1 boolean := true;
    res2 boolean := true;
    res3 boolean := true;
    tmp boolean := true;
BEGIN
   FOR condition IN SELECT  * FROM jsonb_array_elements(conditionArray) LOOP
       IF condition->'all' IS NOT NULL
          THEN SELECT rules."checkAllConditions"(condition->'all', params) INTO res2;
      ELSIF condition->'any' IS NOT NULL
          THEN SELECT rules."checkAnyConditions"(condition->'any', params) INTO res2;
      ELSIF condition->'fact' IS NOT NULL
          THEN 
            SELECT rules."assertFact"(condition::jsonb, params) INTO tmp;
            SELECT res3 AND tmp INTO res3;
      ELSE
          SELECT true INTO tmp;
          SELECT res3 AND tmp INTO res3;
      END IF;
   END LOOP;
  RETURN res1 AND res2 AND res3;
END;
$$;
CREATE FUNCTION rules."checkAnyConditions"(conditionarray jsonb, params jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    condition jsonb;
    res1 boolean := false;
    res2 boolean := false;
    res3 boolean := false;
    tmp boolean := false;
BEGIN
    FOR condition IN SELECT * FROM jsonb_array_elements(conditionArray) LOOP
        IF condition->'all' IS NOT NULL
            THEN SELECT rules."checkAllConditions"(condition->'all', params) INTO res2;
        ELSIF condition->'any' IS NOT NULL
          THEN SELECT rules."checkAnyConditions"(condition->'any', params) INTO res2;
        ELSIF condition->'fact' IS NOT NULL
          THEN 
            SELECT rules."assertFact"(condition::jsonb, params) INTO tmp;
            SELECT res3 OR tmp INTO res3;
        ELSE
          SELECT true INTO tmp;
          SELECT res3 OR tmp INTO res3;
      END IF;
   END LOOP;
  RETURN res1 OR res2 OR res3;
END;
$$;
CREATE FUNCTION rules."customerEmail"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerEmailFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."customerEmailFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    customerEmail text;
    operators text[] := ARRAY['contains', 'doesNotContain', 'equal', 'notEqual'];
BEGIN
    IF params->'read'
        THEN RETURN jsonb_build_object('id', 'customerEmail', 'fact', 'customerEmail', 'title', 'Customer Email', 'value', '{ "type" : "text" }'::json,'argument','keycloakId', 'operators', operators);
    ELSE
        SELECT email FROM crm."customer" WHERE "keycloakId" = (params->>'keycloakId')::text INTO customerEmail;
        RETURN jsonb_build_object('value', customerEmail, 'valueType','text','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."customerReferralCodeFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    referralCode text ;
     operators text[] := ARRAY['contains', 'doesNotContain', 'equal', 'notEqual'];
BEGIN
IF params->'read'
        THEN RETURN json_build_object('id', 'customerReferralCode', 'fact', 'customerReferralCode', 'title', 'Customer Referral Code', 'value', '{ "type" : "text" }'::json,'argument','keycloakId', 'operators', operators);
    ELSE
          SELECT "referralCode" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referralCode;
          RETURN json_build_object('value', referralCode , 'valueType','text','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."customerReferredByCode"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerReferredByCodeFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."customerReferredByCodeFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    code text ;
    operators text[] := ARRAY['equal', 'notEqual'];
BEGIN
    IF (params->'read')::boolean = true
        THEN RETURN json_build_object('id', 'customerReferredByCode', 'fact', 'customerReferredByCode', 'title', 'Customer is Referred', 'value', '{ "type" : "text" }'::json,'argument','keycloakId', 'operators', operators);
    ELSE
        SELECT "referredByCode" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text AND "brandId" = (params->>'brandId')::int INTO code;
        IF code IS NULL THEN
          RETURN json_build_object('value', 'false' , 'valueType','text','argument','keycloakId, brandId');
        ELSE
          RETURN json_build_object('value', 'true' , 'valueType','text','argument','keycloakId, brandId');
        END IF;
    END IF;
END;
$$;
CREATE FUNCTION rules."customerReferrerCode"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerReferrerCodeFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."customerReferrerCodeFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    referredByCode text ;
     operators text[] := ARRAY['contains', 'doesNotContain', 'equal', 'notEqual'];
BEGIN
IF params->'read'
        THEN RETURN json_build_object('id', 'customerReferrerCode', 'fact', 'customerReferrerCode', 'title', 'Customer Referrer Code', 'value', '{ "type" : "text" }'::json,'argument','keycloakId', 'operators', operators);
    ELSE
          SELECT "referredByCode" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referredByCode;
          RETURN json_build_object('value', referredByCode , 'valueType','text','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."customerSubscriptionSkipCountWithDuration"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerSubscriptionSkipCountWithDurationFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."customerSubscriptionSkipCountWithDurationFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    subscriptionSkipCount integer := 0;
    enddate timestamp := current_timestamp;
    startdate timestamp := enddate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'customerSubscriptionSkipCountWithDuration', 'fact', 'orderCountWithDuration', 'title', 'Order Count With Duration', 'value', '{ "type" : "int", "duration" : true }'::json ,'argument','keycloakId', 'operators', operators);
    ELSE
    select count(*) into subscriptionSkipCount from "subscription"."subscriptionOccurence_customer" where "keycloakId" = (params->>'keycloakId')::text and "isSkipped" = true and ("subscriptionOccurenceId" in (select "id" from "subscription"."subscriptionOccurence" where "fulfillmentDate" > startdate and "fulfillmentDate" < enddate ));
          RETURN json_build_object('value',subscriptionSkipCount,'valueType','integer','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."getConditionDisplay"(conditionid integer, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb := ('Following are the conditions');
    condition record;
BEGIN
    SELECT * FROM rules.conditions WHERE id = conditionId INTO condition;
    IF condition.condition->'all' IS NOT NULL
        THEN SELECT rules."getAllConditionsDisplay"(condition.condition->'all', params) || res;
    ELSIF condition.condition->'any' IS NOT NULL
        THEN SELECT rules."getAnyConditionsDisplay"(condition.condition->'any', params) || res;
    END IF;
    RETURN res;
END;
$$;
CREATE FUNCTION rules."getFactTitle"(fact text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE readFact jsonb;
BEGIN
    select call('SELECT rules."' || fact || 'Func"' || '({"read": true})') into readFact;
    return (readFact->'title')::text;
END;
$$;
CREATE FUNCTION rules."getFactTitle"(fact text, params jsonb) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE readFact jsonb;
BEGIN
    select call('SELECT rules."' || fact || 'Func"' || '(' || '''' || params || '''' || ')') into readFact;
    return (readFact->'title')::text;
END;
$$;
CREATE FUNCTION rules."getFactValue"(fact text, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN call('SELECT rules."' || fact || 'Func"' || '(' || '''' || params || '''' || ')');
END;
$$;
CREATE FUNCTION rules."isCartSubscription"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."isCartSubscriptionFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."isCartSubscriptionFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    cartSource text;
    isSubscription text;
    operators text[] := ARRAY['equal', 'notEqual'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('fact', 'isCartSubscription', 'title', 'is Cart from subscription', 'value', '{ "type" : "text" }'::json,'argument','cartId','operators', operators);
    ELSE
        select "source" into cartSource from "order"."cart" where id = (params->>'cartId')::integer;
        if cartSource = 'subscription' then 
        isSubscription := 'true' ; 
        else 
        isSubscription := 'false' ; 
        end if;
        RETURN jsonb_build_object('value', isSubscription, 'valueType','boolean','argument','cartid');
    END IF;
END;
$$;
CREATE TABLE rules.conditions (
    id integer DEFAULT public.defaultid('rules'::text, 'conditions'::text, 'id'::text) NOT NULL,
    condition jsonb,
    app text
);
CREATE FUNCTION rules."isConditionValid"(condition rules.conditions, params jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res boolean;
    x int;
BEGIN
    SELECT id FROM crm.reward WHERE "conditionId" = condition.id INTO x;
    IF x IS NOT NULL THEN
        params := params || jsonb_build_object('rewardId', x);
    END IF;
    IF x IS NULL THEN
        SELECT id FROM crm.campaign WHERE "conditionId" = condition.id INTO x;
        IF x IS NOT NULL THEN
            params := params || jsonb_build_object('campaignId', x);
        END IF;
    END IF;
    IF x IS NULL THEN
        SELECT id FROM crm.coupon WHERE "visibleConditionId" = condition.id INTO x;
        IF x IS NOT NULL THEN
            params := params || jsonb_build_object('couponId', x);
        END IF;
    END IF;
    SELECT rules."isConditionValidFunc"(condition.id, params) INTO res;
    RETURN res;
END;
$$;
CREATE FUNCTION rules."isConditionValidFunc"(conditionid integer, params jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res boolean;
    condition record;
BEGIN
    SELECT * FROM rules.conditions WHERE id = conditionId INTO condition;
    IF condition.condition->'all' IS NOT NULL
        THEN SELECT rules."checkAllConditions"(condition.condition->'all', params) INTO res;
    ELSIF condition.condition->'any' IS NOT NULL
        THEN SELECT rules."checkAnyConditions"(condition.condition->'any', params) INTO res;
    ELSE
        SELECT true INTO res;
    END IF;
    RETURN res;
END;
$$;
CREATE FUNCTION rules."isCustomerReferred"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."isCustomerReferredFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."isCustomerReferredFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    referredByCode text ;
    value text := 'false';
     operators text[] := ARRAY['contains', 'doesNotContain', 'equal', 'notEqual'];
BEGIN
IF params->'read'
        THEN RETURN json_build_object('id', 'isCustomerReferred', 'fact', 'isCustomerReferred', 'title', 'Is Customer Referred', 'value', '{ "type" : "text" }'::json,'argument','keycloakId', 'operators', operators);
    ELSE
          SELECT "referredByCode" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referredByCode;
          IF referredByCode is not null then 
            value := 'true';
          end if;
          RETURN json_build_object('value', value , 'valueType','text','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfCustomerReferred"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfCustomerReferredFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfCustomerReferredFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    referralCode text ;
    referredCount int;
    value boolean := false;
     operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
IF params->'read'
        THEN RETURN json_build_object('id', 'numberOfCustomerReferred', 'fact', 'numberOfCustomerReferred', 'title', 'Number Of Customer Referred', 'value', '{ "type" : "int" }'::json,'argument','keycloakId', 'operators', operators);
    ELSE
          SELECT "referralCode" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referralCode;
          select count(*) from crm."customerReferral" WHERE "referredByCode" = referralCode INTO referredCount;
          RETURN json_build_object('value', referredCount , 'valueType','number','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfSubscriptionAddOnProducts"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfSubscriptionAddOnProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfSubscriptionAddOnProductsFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    addedAddOnProductsCount int := 0;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
      IF params->'read' THEN 
    RETURN json_build_object('fact', 'cartContainsAddOnProducts', 'title', 'Cart Contains AddOn Products', 'operators', operators);
    ELSE
    Select coalesce(COUNT(*), 0) INTO addedAddOnProductsCount FROM "order"."cartItem" WHERE "cartId" = (params->>'cartId')::integer AND "isAddOn" = true AND "parentCartItemId" IS NULL;
    RETURN jsonb_build_object('value', addedAddOnProductsCount, 'valueType', 'integer', 'argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."numberOfSuccessfulCustomerReferred"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfSuccessfulCustomerReferredFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."numberOfSuccessfulCustomerReferredFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    referralCode text ;
    referredCount int;
    value boolean := false;
     operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
IF params->'read'
        THEN RETURN json_build_object('id', 'numberOfSuccessfulCustomerReferred', 'fact', 'numberOfSuccessfulCustomerReferred', 'title', 'Number Of Customer Successfully Referred', 'value', '{ "type" : "int" }'::json,'argument','keycloakId', 'operators', operators);
    ELSE
          SELECT "referralCode" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referralCode;
          select count(*) from crm."customerReferral" WHERE "referredByCode" = referralCode and "referralStatus" = 'COMPLETED' INTO referredCount;
          RETURN json_build_object('value', referredCount , 'valueType','number','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."orderCountWithDuration"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."orderCountWithDurationFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."orderCountWithDurationFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    dateArray timestamp[];
    dateArr timestamp;
    orderCount integer := 0;
    enddate timestamp := current_timestamp;
    startdate timestamp := enddate - (params->>'duration')::interval;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'orderCountWithDuration', 'fact', 'orderCountWithDuration', 'title', 'Order Count With Duration', 'value', '{ "type" : "int", "duration" : true }'::json ,'argument','keycloakId', 'operators', operators);
    ELSE
          SELECT COUNT(*) FROM "order"."cart" WHERE "customerKeycloakId" = (params->>'keycloakId')::text AND "paymentStatus" = 'SUCCEEDED' AND "created_at" > startdate AND "created_at" <  enddate INTO orderCount;
          RETURN json_build_object('value',orderCount,'valueType','integer','argument','keycloakId');
    END IF;
END;
$$;
CREATE FUNCTION rules."referralStatus"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT crm."referralStatusFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."referralStatusFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    referralStatus text ;
BEGIN
  SELECT "status" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referralStatus;
  RETURN json_build_object('value', referralStatus, 'valueType','text','argument','keycloakId');
END;
$$;
CREATE FUNCTION rules."rruleHasDateFunc"(rrule _rrule.rruleset, d timestamp without time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res boolean;
BEGIN
  SELECT rrule @> d into res;
  RETURN res;
END;
$$;
CREATE FUNCTION rules."runWithOperator"(operator text, vals jsonb) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res boolean := false;
BEGIN
    -- IF vals->>'fact' IS NOT NULL THEN
        IF operator = 'rruleHasDate'
            THEN SELECT rules."rruleHasDateFunc"((vals->'condition')::text::jsonb::_rrule.rruleset, (vals->'fact')::text::timestamp) INTO res;
        ELSIF operator = 'equal'
            THEN SELECT (vals->'fact')::text = (vals->'condition')::text INTO res;
        ELSIF operator = 'notEqual'
            THEN SELECT (vals->'fact')::text != (vals->'condition')::text INTO res;
        ELSIF operator = 'greaterThan'
            THEN SELECT (vals->>'fact')::numeric > (vals->>'condition')::numeric INTO res;
        ELSIF operator = 'greaterThanInclusive'
            THEN SELECT (vals->>'fact')::numeric >= (vals->>'condition')::numeric INTO res;
        ELSIF operator = 'lessThan'
            THEN SELECT (vals->>'fact')::numeric < (vals->>'condition')::numeric INTO res;
        ELSIF operator = 'lessThanInclusive'
            THEN SELECT (vals->>'fact')::numeric <= (vals->>'condition')::numeric INTO res;
        ELSIF operator = 'contains'
            THEN SELECT vals->>'fact' LIKE CONCAT('%', vals->>'condition', '%') INTO res;
        ELSIF operator = 'doesNotContain'
            THEN SELECT vals->>'fact' NOT LIKE CONCAT('%', vals->>'condition', '%') INTO res;
        ELSIF operator = 'in'
            THEN SELECT vals->>'condition' = ANY(ARRAY(SELECT jsonb_array_elements_text(vals->'fact'))) INTO res;
        ELSIF operator = 'notIn'
            THEN SELECT vals->>'condition' != ALL(ARRAY(SELECT jsonb_array_elements_text(vals->'fact'))) INTO res;
        ELSE
            SELECT false INTO res;
        END IF;
    -- END IF;
    RETURN res;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartComboProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartComboProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartComboProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfCartComboProduct', 'fact', 'totalNumberOfCartComboProduct', 'title', 'Total Number Of Combo Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'combo'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartCustomizableProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartCustomizableProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartCustomizableProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfCartCustomizableProduct', 'fact', 'totalNumberOfCartCustomizableProduct', 'title', 'Total Number Of Customizable Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartItem" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        Select "type" from "products"."product" where "id" = "cartItem"."productId" into productType;
            IF productType = 'customizable'
             THEN SELECT "cartItem"."productId" INTO productId;
              productIdArray = productIdArray || productId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartInventoryProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartInventoryProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartInventoryProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfCartInventoryProduct', 'fact', 'totalNumberOfCartInventoryProduct', 'title', 'Total Number Of Inventory Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'inventory' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productOptionIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartMealKitProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartMealKitProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartMealKitProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfCartMealKitProduct', 'fact', 'totalNumberOfCartMealKitProduct', 'title', 'Total Number Of Meal Kit Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'mealKit' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productOptionIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartReadyToEatProduct"(fact rules.facts, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartReadyToEatProductFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION rules."totalNumberOfCartReadyToEatProductFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfCartReadyToEatProduct', 'fact', 'totalNumberOfCartReadyToEatProduct', 'title', 'Total Number Of Ready To Eat Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        FOR "cartProduct" IN SELECT * from "order"."cartItem" where "cartId" = (params->>'cartId')::integer LOOP
        select "productOptionId" from "order"."cartItem" where "parentCartItemId" = "cartProduct"."id" into productOptionId;
            SELECT "type" from "products"."productOption" where "id" = productOptionId into productOptionType;
            IF productOptionType = 'readyToEat' then
              productOptionIdArray = productOptionIdArray || productOptionId;
            END IF;
        END LOOP;
        RETURN json_build_object('value', coalesce(array_length(productOptionIdArray, 1), 0) , 'valueType','integer','argument','cartid');
    END IF;
END;
$$;
CREATE FUNCTION safety.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION settings.define_owner_role() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
role_Id int;
BEGIN
    IF NEW."isOwner" = true AND NEW."keycloakId" is not null THEN
    select "id" into role_Id from "settings"."role" where "title" = 'admin';
    insert into "settings"."user_role" ("userId", "roleId") values (
    NEW."keycloakId", role_Id
    );
    END IF;
    RETURN NULL;
END;
$$;
CREATE TABLE settings."operationConfig" (
    id integer DEFAULT public.defaultid('settings'::text, 'operationConfig'::text, 'id'::text) NOT NULL,
    "stationId" integer,
    "labelTemplateId" integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    "packagingId" integer
);
CREATE FUNCTION settings."operationConfigName"(opconfig settings."operationConfig") RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    station text;
    template text;
BEGIN
    SELECT name FROM "deviceHub"."labelTemplate" WHERE id = opConfig."labelTemplateId" INTO template;
    SELECT name FROM settings."station" WHERE id = opConfig."stationId" INTO station;
    RETURN station || ' - ' || template;
END;
$$;
CREATE FUNCTION settings.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION "simpleRecipe"."getRecipeRichResult"(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb := '{ "@context": "https://schema.org/", "@type": "Recipe" }';
    yield record;
    sachet record;
    ingredients text[];
    steps jsonb[];
    proc jsonb;
    step jsonb;
BEGIN
    res := res || jsonb_build_object('name', recipe.name, 'image', COALESCE(recipe.image, ''), 'keywords', recipe.name, 'recipeCuisine', recipe.cuisine);
    IF recipe.description IS NOT NULL THEN
        res := res || jsonb_build_object('description', recipe.description);
    END IF;
    IF recipe.author IS NOT NULL THEN
        res := res || jsonb_build_object('author', jsonb_build_object('@type', 'Person', 'name', recipe.author));
    END IF;
    IF recipe."cookingTime" IS NOT NULL THEN
        res := res || jsonb_build_object('cookTime', 'PT' || recipe."cookingTime" || 'M');
    END IF;
    IF recipe."showIngredients" = true THEN
        SELECT * FROM "simpleRecipe"."simpleRecipeYield" WHERE "simpleRecipeId" = recipe.id ORDER BY yield DESC LIMIT 1 INTO yield; 
        IF yield IS NOT NULL THEN
            res := res || jsonb_build_object('recipeYield', yield.yield->>'serving');
            FOR sachet IN SELECT * FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = yield.id LOOP
                SELECT array_append(ingredients, sachet."slipName") INTO ingredients;
            END LOOP;
            res := res || jsonb_build_object('recipeIngredient', ingredients);
        END IF;
    END IF;
    IF recipe."showProcedures" = true AND recipe."procedures" IS NOT NULL THEN
        FOR proc IN SELECT * FROM jsonb_array_elements(recipe."procedures") LOOP
            FOR step IN SELECT * FROM jsonb_array_elements(proc->'steps') LOOP
                SELECT array_append(steps, jsonb_build_object('@type', 'HowToStep', 'name', step->>'title', 'text', step->>'description', 'image', step->'assets'->'images'->0->>'url')) INTO steps;
            END LOOP;
        END LOOP;
        res := res || jsonb_build_object('recipeInstructions', steps);
    END IF;
    return res;
END;
$$;
CREATE FUNCTION "simpleRecipe".issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    ingredientsCount int;
    instructionSetsCount int;
BEGIN
    SELECT count(*) FROM "simpleRecipe"."simpleRecipe_ingredient_processing" WHERE "simpleRecipeId" = recipe.id AND "isArchived" = false INTO ingredientsCount;
    SELECT count(*) FROM "instructions"."instructionSet" WHERE "simpleRecipeId" = recipe.id INTO instructionSetsCount;
    IF recipe.utensils IS NULL OR jsonb_array_length(recipe.utensils) = 0
        THEN return json_build_object('status', false, 'error', 'Recipe should have untensils associated!');
    ELSEIF ingredientsCount = 0
        THEN return json_build_object('status', false, 'error', 'Recipe should have ingredients!');
    ELSEIF instructionSetsCount = 0
        THEN return json_build_object('status', false, 'error', 'Recipe should have cooking steps!');
    ELSEIF recipe.assets IS NULL OR JSONB_ARRAY_LENGTH(recipe.assets->'images') = 0
        THEN return json_build_object('status', false, 'error', 'At least one image should be provided!');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION "simpleRecipe".set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION "simpleRecipe"."updateSimpleRecipeYield_ingredientSachet"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
   update "simpleRecipe"."simpleRecipeYield_ingredientSachet"
   SET "simpleRecipeId" = (select "simpleRecipeId" from "simpleRecipe"."simpleRecipeYield" where id = NEW."recipeYieldId");
    RETURN NULL;
END;
$$;
CREATE TABLE "simpleRecipe"."simpleRecipeYield" (
    id integer DEFAULT public.defaultid('simpleRecipe'::text, 'simpleRecipeYield'::text, 'id'::text) NOT NULL,
    "simpleRecipeId" integer NOT NULL,
    yield jsonb NOT NULL,
    "isArchived" boolean DEFAULT false NOT NULL,
    quantity numeric,
    unit text,
    serving numeric
);
CREATE FUNCTION "simpleRecipe"."yieldAllergens"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    arr jsonb;
    temp jsonb;
    data jsonb := '[]';
    mode record;
BEGIN
    FOR mode IN SELECT * FROM ingredient."modeOfFulfillment" WHERE "ingredientSachetId" = ANY(SELECT "ingredientSachetId" FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = yield.id) LOOP
        IF mode."bulkItemId" IS NOT NULL THEN
            SELECT allergens FROM inventory."bulkItem" WHERE id = mode."bulkItemId" INTO arr;
            FOR temp IN SELECT * FROM jsonb_array_elements(arr) LOOP
                data := data || temp;
            END LOOP;
        ELSIF mode."sachetItemId" IS NOT NULL THEN
            SELECT allergens FROM inventory."bulkItem" WHERE id = (SELECT "bulkItemId" FROM inventory."sachetItem" WHERE id = mode."sachetItemId") INTO arr;
            FOR temp IN SELECT * FROM jsonb_array_elements(arr) LOOP
                data := data || temp;
            END LOOP;
        ELSE
            CONTINUE;
        END IF;
    END LOOP;
    RETURN data;
END;
$$;
CREATE FUNCTION "simpleRecipe"."yieldCost"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    bridge record;
    cost numeric;
    finalCost numeric := 0;
BEGIN
    FOR bridge IN SELECT "ingredientSachetId" FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = yield.id LOOP
        SELECT ingredient."sachetCost"(bridge."ingredientSachetId") into cost;
        IF cost IS NOT NULL
            THEN finalCost = finalCost + cost;
        END IF;
    END LOOP;
    RETURN finalCost;
END
$$;
CREATE FUNCTION "simpleRecipe"."yieldNutritionalInfo"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    bridge record;
    info jsonb;
    infoArr jsonb[];
    finalInfo jsonb;
BEGIN
    FOR bridge IN SELECT "ingredientSachetId" FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = yield.id LOOP
        SELECT ingredient."sachetNutritionalInfo"(bridge."ingredientSachetId") into info;
        IF info IS NOT NULL
            THEN SELECT jsonb_build_object(
                        'per', (info->>'per')::numeric,
                        'iron', COALESCE(CAST(finalInfo->>'iron'AS decimal) + CAST(info->>'iron' AS decimal), 0),
                        'sodium', COALESCE(CAST(finalInfo->>'sodium' AS decimal) + CAST(info->>'sodium' AS decimal), 0),
                        'sugars', COALESCE(CAST(finalInfo->>'sugars' AS decimal) + CAST(info->>'sugars' AS decimal), 0),
                        'calcium', COALESCE(CAST(finalInfo->>'calcium' AS decimal) + CAST(info->>'calcium' AS decimal), 0),
                        'protein', COALESCE(CAST(finalInfo->>'protein' AS decimal) + CAST(info->>'protein' AS decimal), 0),
                        'calories', COALESCE(CAST(finalInfo->>'calories' AS decimal) + CAST(info->>'calories' AS decimal), 0),
                        'totalFat', COALESCE(CAST(finalInfo->>'totalFat' AS decimal) + CAST(info->>'totalFat' AS decimal), 0),
                        'transFat', COALESCE(CAST(finalInfo->>'transFat' AS decimal) + CAST(info->>'transFat' AS decimal), 0),
                        'vitaminA', COALESCE(CAST(finalInfo->>'vitaminA' AS decimal) + CAST(info->>'vitaminA' AS decimal), 0),
                        'vitaminC', COALESCE(CAST(finalInfo->>'vitaminC' AS decimal) + CAST(info->>'vitaminC' AS decimal), 0),
                        'cholesterol', COALESCE(CAST(finalInfo->>'cholesterol' AS decimal) + CAST(info->>'cholesterol' AS decimal), 0),
                        'dietaryFibre', COALESCE(CAST(finalInfo->>'dietaryFibre' AS decimal) + CAST(info->>'dietaryFibre' AS decimal), 0),
                        'saturatedFat', COALESCE(CAST(finalInfo->>'saturatedFat' AS decimal) + CAST(info->>'saturatedFat' AS decimal), 0),
                        'totalCarbohydrates', COALESCE(CAST(finalInfo->>'totalCarbohydrates' AS decimal) + CAST(info->>'totalCarbohydrates' AS decimal), 0)
                    ) into finalInfo;
        END IF;
    END LOOP;
    RETURN finalInfo;
END
$$;
CREATE TABLE subscription."subscriptionOccurence_addOn" (
    id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionOccurence_addOn'::text, 'id'::text) NOT NULL,
    "subscriptionOccurenceId" integer,
    "unitPrice" numeric NOT NULL,
    "productCategory" text,
    "isAvailable" boolean DEFAULT true NOT NULL,
    "isVisible" boolean DEFAULT true NOT NULL,
    "isSingleSelect" boolean DEFAULT false NOT NULL,
    "subscriptionId" integer,
    "productOptionId" integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE FUNCTION subscription."addOnCartItem"(x subscription."subscriptionOccurence_addOn") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    item jsonb;
BEGIN
    SELECT products."productCartItemById"(x."productOptionId") INTO item;
    item:=item || jsonb_build_object('isAddOn', true);
    item:=item || jsonb_build_object('unitPrice', x."unitPrice");
    item:=item || jsonb_build_object('subscriptionOccurenceAddOnProductId', x.id);
    RETURN item;
END
$$;
CREATE FUNCTION subscription."assignWeekNumberToSubscriptionOccurence"("subscriptionOccurenceId" integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    fulfillmentDate timestamp;
    now timestamp := now();
    datediff integer;
BEGIN
   select "fulfillmentDate" from subscription."subscriptionOccurence" where id = "subscriptionOccurenceId" into fulfillmentDate;
   select (fulfillmentDate::date - now::date)/7 into datediff;
    RETURN datediff;
END
$$;
CREATE TABLE subscription."subscriptionOccurence" (
    id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionOccurence'::text, 'id'::text) NOT NULL,
    "fulfillmentDate" date NOT NULL,
    "cutoffTimeStamp" timestamp without time zone NOT NULL,
    "subscriptionId" integer NOT NULL,
    "startTimeStamp" timestamp without time zone,
    assets jsonb,
    "subscriptionAutoSelectOption" text,
    "subscriptionItemCountId" integer,
    "subscriptionServingId" integer,
    "subscriptionTitleId" integer
);
CREATE FUNCTION subscription."calculateIsValid"(occurence subscription."subscriptionOccurence") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    currentTime timestamp;
    cutoffTime timestamp;
BEGIN
    SELECT NOW() into currentTime;
    SELECT occurence."cutoffTimeStamp" into cutoffTime;
RETURN
    currentTime < cutoffTime;
END
$$;
CREATE FUNCTION subscription."calculateIsVisible"(occurence subscription."subscriptionOccurence") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    currentTime timestamp;
    startTime timestamp;
BEGIN
    SELECT NOW() into currentTime ;
    SELECT occurence."startTimeStamp" into startTime;
RETURN
    currentTime > startTime;
END
$$;
CREATE TABLE subscription."subscriptionOccurence_product" (
    "subscriptionOccurenceId" integer,
    "addOnPrice" numeric DEFAULT 0,
    "addOnLabel" text,
    "productCategory" text,
    "isAvailable" boolean DEFAULT true,
    "isVisible" boolean DEFAULT true,
    "isSingleSelect" boolean DEFAULT true NOT NULL,
    "subscriptionId" integer,
    id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionOccurence_product'::text, 'id'::text) NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "isAutoSelectable" boolean DEFAULT true NOT NULL,
    "productOptionId" integer NOT NULL
);
CREATE FUNCTION subscription."cartItem"(x subscription."subscriptionOccurence_product") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    item jsonb;
    productType text;
    subscriptionId int;
    itemCountId int;
    itemCount int;
    itemCountPrice numeric;
    unitPrice numeric;
BEGIN
    IF x."subscriptionOccurenceId" IS NOT NULL THEN
        SELECT "subscriptionId" INTO subscriptionId FROM subscription."subscriptionOccurence" WHERE id = x."subscriptionOccurenceId";
    ELSE 
        subscriptionId := x."subscriptionId";
    END IF;
    SELECT "subscriptionItemCountId" INTO itemCountId FROM subscription.subscription WHERE id = subscriptionId;
    SELECT price, count INTO itemCountPrice, itemCount FROM subscription."subscriptionItemCount" WHERE id = itemCountId;
    SELECT products."productCartItemById"(x."productOptionId") INTO item;
    item:=item || jsonb_build_object('addOnLabel',x."addOnLabel", 'addOnPrice',x."addOnPrice");
    unitPrice := (itemCountPrice / itemCount) + COALESCE(x."addOnPrice", 0);
    item:=item || jsonb_build_object('isAddOn', false);
    item:=item || jsonb_build_object('unitPrice', unitPrice);
    item:=item || jsonb_build_object('subscriptionOccurenceProductId', x.id);
    RETURN item;
END
$$;
CREATE FUNCTION subscription."customerSubscriptionReport"(brand_customerid integer, status text) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   subscriptionId int;
   total int := 0;
BEGIN
    select "subscriptionId" from "crm"."brand_customer" where id = brand_customerId into subscriptionId;
    IF subscriptionId is NOT NULL then
    IF status = 'All' THEN
    select count(*) from subscription."subscriptionOccurence_customer" where "brand_customerId" = brand_customerId and "subscriptionId" = subscriptionId into total;
   ELSIF
   status = 'Skipped' THEN 
    select count(*) from subscription."subscriptionOccurence_customer" where "brand_customerId" = brand_customerId and "subscriptionId" = subscriptionId and "isSkipped" = true into total;
   END IF;
   END IF;
    return total;
END;
$$;
CREATE TABLE subscription."subscriptionOccurence_customer" (
    "subscriptionOccurenceId" integer NOT NULL,
    "keycloakId" text NOT NULL,
    "cartId" integer,
    "isSkipped" boolean DEFAULT false NOT NULL,
    "isAuto" boolean,
    "brand_customerId" integer NOT NULL,
    "subscriptionId" integer
);
CREATE FUNCTION subscription."isCartValid"(record subscription."subscriptionOccurence_customer") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    subscriptionId int;
    itemCountId int;
    itemCount int;
    addedProductsCount int := 0;
    pendingProductsCount int := 0;
    result jsonb := '{}';
BEGIN
    IF record."cartId" IS NULL THEN
        result := result || jsonb_build_object('hasCart', false);
    ELSIF record."cartId" IS NOT NULL THEN
        result := result || jsonb_build_object('hasCart', true);
    END IF;
    SELECT "subscriptionId" INTO subscriptionId FROM subscription."subscriptionOccurence" WHERE id = record."subscriptionOccurenceId";
    SELECT "subscriptionItemCountId" INTO itemCountId FROM subscription.subscription WHERE id = subscriptionId;
    SELECT count FROM subscription."subscriptionItemCount" WHERE id = itemCountId INTO itemCount;
    SELECT COALESCE(COUNT(*), 0) INTO addedProductsCount FROM "order"."cartItem" WHERE "cartId" = record."cartId" AND "isAddOn" = false AND "parentCartItemId" IS NULL;
    result := result || jsonb_build_object('addedProductsCount', addedProductsCount);
    pendingProductsCount := itemCount - addedProductsCount;
    result := result || jsonb_build_object('pendingProductsCount', pendingProductsCount);
    IF itemCount = addedProductsCount THEN
        result := result || jsonb_build_object('itemCountValid', true, 'itemCountValidComment', 'You' || '''' || 're all set!');
    ELSIF itemCount < addedProductsCount THEN
        result := result || jsonb_build_object('itemCountValid', false, 'itemCountValidComment', 'Your cart is overflowing!');
    ELSIF itemCount > addedProductsCount THEN
        result := result || jsonb_build_object('itemCountValid', false, 'itemCountValidComment', 'Add more products!');
    END IF;
    return result;
END;
$$;
CREATE TABLE subscription."subscriptionItemCount" (
    id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionItemCount'::text, 'id'::text) NOT NULL,
    "subscriptionServingId" integer NOT NULL,
    count integer NOT NULL,
    "metaDetails" jsonb,
    price numeric,
    "isActive" boolean DEFAULT false,
    tax numeric DEFAULT 0 NOT NULL,
    "isTaxIncluded" boolean DEFAULT false NOT NULL,
    "subscriptionTitleId" integer,
    "targetedProductSelectionRatio" integer DEFAULT 3
);
CREATE FUNCTION subscription."isSubscriptionItemCountValid"(itemcount subscription."subscriptionItemCount") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    count int;
BEGIN
    SELECT * FROM subscription.subscription where "subscriptionItemCountId" = itemCount.id LIMIT 1 into count;
    IF count > 0 THEN
        return true;
    ELSE
        return false;
    END IF;
END;
$$;
CREATE TABLE subscription."subscriptionServing" (
    id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionServing'::text, 'id'::text) NOT NULL,
    "subscriptionTitleId" integer NOT NULL,
    "servingSize" integer NOT NULL,
    "metaDetails" jsonb,
    "defaultSubscriptionItemCountId" integer,
    "isActive" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION subscription."isSubscriptionServingValid"(serving subscription."subscriptionServing") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    count int;
BEGIN
    SELECT * FROM subscription."subscriptionItemCount" where "subscriptionServingId" = serving.id AND "isActive" = true LIMIT 1 into count;
    IF count > 0 THEN
        return true;
    ELSE
        PERFORM subscription."toggleServingState"(serving.id, false);
        return false;
    END IF;
END;
$$;
CREATE TABLE subscription."subscriptionTitle" (
    id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionTitle'::text, 'id'::text) NOT NULL,
    title text NOT NULL,
    "metaDetails" jsonb,
    "defaultSubscriptionServingId" integer,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "isActive" boolean DEFAULT false NOT NULL
);
CREATE FUNCTION subscription."isSubscriptionTitleValid"(title subscription."subscriptionTitle") RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    count int;
BEGIN
    SELECT * FROM subscription."subscriptionServing" where "subscriptionTitleId" = title.id AND "isActive" = true LIMIT 1 into count;
    IF count > 0 THEN
        return true;
    ELSE
        PERFORM subscription."toggleTitleState"(title.id, false);
        return false;
    END IF;
END;
$$;
CREATE FUNCTION subscription.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION subscription."subscriptionOccurenceWeekRank"(record subscription."subscriptionOccurence") RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
BEGIN
    RETURN "subscription"."assignWeekNumberToSubscriptionOccurence"(record.id);
END
$$;
CREATE FUNCTION subscription."toggleServingState"(servingid integer, state boolean) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE subscription."subscriptionServing"
    SET "isActive" = state
    WHERE "id" = servingId;
END;
$$;
CREATE FUNCTION subscription."toggleTitleState"(titleid integer, state boolean) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE subscription."subscriptionTitle"
    SET "isActive" = state
    WHERE "id" = titleId;
END;
$$;
CREATE FUNCTION subscription."updateSubscription"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
   UPDATE "subscription"."subscription"
SET "subscriptionTitleId" = (select "subscriptionTitleId" from "subscription"."subscriptionItemCount" where id = NEW."subscriptionItemCountId"),
"subscriptionServingId" = (select "subscriptionServingId" from "subscription"."subscriptionItemCount" where id = NEW."subscriptionItemCountId")
WHERE id = NEW.id;
    RETURN null;
END;
$$;
CREATE FUNCTION subscription."updateSubscriptionItemCount"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE "subscription"."subscriptionItemCount"
SET "subscriptionTitleId" = (select "subscriptionTitleId" from "subscription"."subscriptionServing" where id = NEW."subscriptionServingId")
WHERE id = NEW.id;
    RETURN null;
END;
$$;
CREATE FUNCTION subscription."updateSubscriptionOccurence"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
   UPDATE "subscription"."subscriptionOccurence"
SET "subscriptionTitleId" = (select "subscriptionTitleId" from "subscription"."subscription" where id = NEW."subscriptionId"),
"subscriptionServingId" = (select "subscriptionServingId" from "subscription"."subscription" where id = NEW."subscriptionId"),
"subscriptionItemCountId" = (select "subscriptionItemCountId" from "subscription"."subscription" where id = NEW."subscriptionId")
WHERE id = NEW.id;
    RETURN null;
END;
$$;
CREATE FUNCTION subscription."updateSubscriptionOccurence_customer"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    subs_id integer;
    _new record;
BEGIN
select "subscriptionId" INTO subs_id from "subscription"."subscriptionOccurence" where id = NEW."subscriptionOccurenceId";
    _new := NEW;
  _new."subscriptionId" = subs_id;
  RETURN _new;
END;
$$;
CREATE FUNCTION website.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;
