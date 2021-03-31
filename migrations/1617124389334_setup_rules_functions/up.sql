CREATE
OR REPLACE FUNCTION rules."assertFact"(condition jsonb, params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $ function $ DECLARE x jsonb;

factValue jsonb;

values
    jsonb;

res boolean;

BEGIN x := condition || params;

SELECT
    rules."getFactValue"(condition ->> 'fact', x) INTO factValue;

SELECT
    jsonb_build_object(
        'condition',
        condition -> 'value',
        'fact',
        factValue -> 'value'
    ) INTO
values
;

SELECT
    rules."runWithOperator"(
        condition ->> 'operator',
        values
    ) INTO res;

RETURN res;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."budgetFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE typeof text;

total numeric := 0;

campaignRecord record;

campIds integer array DEFAULT '{}';

queryParams jsonb default '{}' :: jsonb;

endDate timestamp without time zone;

startDate timestamp without time zone;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

query text := '';

BEGIN IF params -> 'read' THEN RETURN jsonb_build_object(
    'id',
    'budget',
    'fact',
    'budget',
    'title',
    'Budget',
    'value',
    '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ comboProducts { id title: name } }" }' :: json,
    'argument',
    'couponId',
    'operators',
    operators
);

END IF;

query := query || 'SELECT ' || (params ->> 'type') :: text || '(' || '"' || (params ->> 'rewardType') :: text || '"' || ')' || ' FROM crm."rewardHistory" WHERE ';

IF (params -> 'perCustomer') :: boolean = true THEN query := query || '"keycloakId" = ' || '''' || (params ->> 'keycloakId') :: text || '''' || ' AND ';

END IF;

IF params ->> 'coverage' = 'Only This' THEN IF params ->> 'couponId' IS NOT NULL THEN query := query || ' "couponId" = ' || (params ->> 'couponId') :: text || 'AND';

ELSIF params ->> 'campaignId' IS NOT NULL THEN query := query || ' "campaignId" = ' || (params ->> 'campaignId') :: text || 'AND';

ELSE query := query;

END IF;

ELSEIF params ->> 'coverage' = 'Sign Up'
OR params ->> 'coverage' = 'Post Order'
OR params ->> 'coverage' = 'Referral' THEN FOR campaignRecord IN
SELECT
    *
FROM
    crm."campaign"
WHERE
    "type" = (params ->> 'coverage') :: text LOOP campIds := campIds || (campaignRecord."id") :: int;

END LOOP;

query := query || ' "campaignId" IN ' || '(' || array_to_string(campIds, ',') || ')' || 'AND';

ELSEIF params ->> 'coverage' = 'coupons' THEN query := query || ' "couponId" IS NOT NULL AND';

ELSEIF params ->> 'coverage' = 'campaigns' THEN query := query || ' "campaignId" IS NOT NULL AND';

ELSE query := query;

END IF;

IF (params ->> 'duration') :: interval IS NOT NULL THEN endDate := now() :: timestamp without time zone;

startDate := endDate - (params ->> 'duration') :: interval;

query := query || ' "created_at" > ' || '''' || startDate || '''' || 'AND "created_at" < ' || '''' || endDate :: timestamp without time zone || '''';

ELSE query := query;

END IF;

EXECUTE query INTO total;

RETURN jsonb_build_object(
    (params ->> 'type') :: text,
    total,
    'query',
    query
);

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartComboProduct"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartComboProductFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartComboProductComponent"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartComboProductComponentFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartComboProductComponentFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartProduct" record;

productType text;

productIdArray integer array DEFAULT '{}';

productId integer;

operators text [] := ARRAY ['in','notIn'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'cartComboProduct',
    'fact',
    'cartComboProduct',
    'title',
    'Cart Contains Combo Product Component',
    'value',
    '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  comboProductComponents { id } }" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartProduct" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
Select
    "type"
from
    "products"."product"
where
    "id" = "cartProduct"."productId" into productType;

IF productType = 'combo' THEN
SELECT
    "comboProductComponentId"
from
    "order"."cartItem"
where
    "parentCartItemId" = "cartProduct"."id" into productId;

productIdArray = productIdArray || productId;

END IF;

END LOOP;

RETURN jsonb_build_object(
    'value',
    productIdArray,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartComboProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartItem" record;

productType text;

productIdArray integer array DEFAULT '{}';

productId integer;

operators text [] := ARRAY ['in','notIn'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'cartComboProduct',
    'fact',
    'cartComboProduct',
    'title',
    'Cart Contains Combo Product',
    'value',
    '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"combo\"}}) { id title: name } }" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartItem" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
Select
    "type"
from
    "products"."product"
where
    "id" = "cartItem"."productId" into productType;

IF productType = 'combo' THEN
SELECT
    "cartItem"."productId" INTO productId;

productIdArray = productIdArray || productId;

END IF;

END LOOP;

RETURN jsonb_build_object(
    'value',
    productIdArray,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartContainsAddOnProducts"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartContainsAddOnProductsFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartContainsAddOnProductsFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE addedAddOnProductsCount int;

operators text [] := ARRAY ['equal', 'notEqual'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'fact',
    'cartContainsAddOnProducts',
    'title',
    'Cart Contains AddOn Products',
    'value',
    '{ "type" : "text" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE
Select
    COUNT(*) INTO addedAddOnProductsCount
FROM
    "order"."cartItem"
WHERE
    "cartId" = (params ->> 'cartId') :: integer
    AND "isAddOn" = true
    AND "parentCartItemId" IS NULL;

if addedAddOnProductsCount > 0 then RETURN jsonb_build_object(
    'value',
    'true',
    'valueType',
    'boolean',
    'argument',
    'cartid'
);

else RETURN jsonb_build_object(
    'value',
    'false',
    'valueType',
    'boolean',
    'argument',
    'cartid'
);

end if;

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartCustomizableProduct"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartCustomizableProductFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartCustomizableProductComponent"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartCustomizableProductComponentFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartCustomizableProductComponentFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartProduct" record;

productType text;

productIdArray integer array DEFAULT '{}';

productId integer;

operators text [] := ARRAY ['in','notIn'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'cartCustomizableProduct',
    'fact',
    'cartCustomizableProduct',
    'title',
    'Cart Contains Combo Product',
    'value',
    '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  CustomizableProductComponents { id } }" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartProduct" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
Select
    "type"
from
    "products"."product"
where
    "id" = "cartProduct"."productId" into productType;

IF productType = 'combo' THEN
SELECT
    "CustomizableProductComponentId"
from
    "order"."cartItem"
where
    "parentCartItemId" = "cartProduct"."id" into productId;

productIdArray = productIdArray || productId;

END IF;

END LOOP;

RETURN jsonb_build_object(
    'value',
    productIdArray,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartCustomizableProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartItem" record;

productType text;

productIdArray integer array DEFAULT '{}';

productId integer;

operators text [] := ARRAY ['in','notIn'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'cartCustomizableProduct',
    'fact',
    'cartCustomizableProduct',
    'title',
    'Cart Contains Customizable Product',
    'value',
    '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"customizable\"}}) { id title: name } }" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartItem" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
Select
    "type"
from
    "products"."product"
where
    "id" = "cartItem"."productId" into productType;

IF productType = 'customizable' THEN
SELECT
    "cartItem"."productId" INTO productId;

productIdArray = productIdArray || productId;

END IF;

END LOOP;

RETURN jsonb_build_object(
    'value',
    productIdArray,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartInventoryProductOption"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartInventoryProductOptionFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartInventoryProductOptionFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartProduct" record;

productOptionType text;

productOptionIdArray integer array DEFAULT '{}';

productOptionId integer;

operators text [] := ARRAY ['in','notIn'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'cartInventoryProductOption',
    'fact',
    'cartInventoryProductOption',
    'title',
    'Cart Contains Inventory Product Option',
    'value',
    '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"inventory\"}}) { id } }" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartProduct" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
select
    "productOptionId"
from
    "order"."cartItem"
where
    "parentCartItemId" = "cartProduct"."id" into productOptionId;

SELECT
    "type"
from
    "products"."productOption"
where
    "id" = productOptionId into productOptionType;

IF productOptionType = 'inventory' then productOptionIdArray = productOptionIdArray || productOptionId;

END IF;

END LOOP;

RETURN jsonb_build_object(
    'value',
    productOptionIdArray,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartItemTotal"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartItemTotalFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartItemTotalFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE total numeric;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF (params ->> 'read') :: boolean = true THEN RETURN json_build_object(
    'id',
    'cartItemTotal',
    'fact',
    'cartItemTotal',
    'title',
    'Cart Item Total',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE
SELECT
    COALESCE(
        (
            SELECT
                SUM("unitPrice")
            FROM
                "order"."cartItem"
            WHERE
                "cartId" = (params ->> 'cartId') :: integer
        ),
        0
    ) INTO total;

RETURN json_build_object(
    'value',
    total,
    'valueType',
    'numeric',
    'arguments',
    'cartId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartMealKitProductOption"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartMealKitProductOptionFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartMealKitProductOptionFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartProduct" record;

productOptionType text;

productOptionIdArray integer array DEFAULT '{}';

productOptionId integer;

operators text [] := ARRAY ['in','notIn'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'cartMealKitProductOption',
    'fact',
    'cartMealKitProductOption',
    'title',
    'Cart Contains Meal Kit Product Option',
    'value',
    '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"mealKit\"}}) { id } }" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartProduct" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
select
    "productOptionId"
from
    "order"."cartItem"
where
    "parentCartItemId" = "cartProduct"."id" into productOptionId;

SELECT
    "type"
from
    "products"."productOption"
where
    "id" = productOptionId into productOptionType;

IF productOptionType = 'mealKit' then productOptionIdArray = productOptionIdArray || productOptionId;

END IF;

END LOOP;

RETURN jsonb_build_object(
    'value',
    productOptionIdArray,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartReadyToEatProductOption"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartReadyToEatProductOptionFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartReadyToEatProductOptionFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartProduct" record;

productOptionType text;

productOptionIdArray integer array DEFAULT '{}';

productOptionId integer;

operators text [] := ARRAY ['in','notIn'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'cartReadyToEatProductOption',
    'fact',
    'cartReadyToEatProductOption',
    'title',
    'Cart Contains Ready to Eat Product Option',
    'value',
    '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"readyToEat\"}}) { id } }" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartProduct" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
select
    "productOptionId"
from
    "order"."cartItem"
where
    "parentCartItemId" = "cartProduct"."id" into productOptionId;

SELECT
    "type"
from
    "products"."productOption"
where
    "id" = productOptionId into productOptionType;

IF productOptionType = 'readyToEat' then productOptionIdArray = productOptionIdArray || productOptionId;

END IF;

END LOOP;

RETURN jsonb_build_object(
    'value',
    productOptionIdArray,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartSimpleProduct"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartSimpleProductFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartSimpleProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartItem" record;

productType text;

productIdArray integer array DEFAULT '{}';

productId integer;

operators text [] := ARRAY ['in','notIn'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'cartSimpleProduct',
    'fact',
    'cartSimpleProductFunc',
    'title',
    'Cart Contains Simple Product',
    'value',
    '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"simple\"}}) { id title: name } }" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartItem" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
Select
    "type"
from
    "products"."product"
where
    "id" = "cartItem"."productId" into productType;

IF productType = 'simple' THEN
SELECT
    "cartItem"."productId" INTO productId;

productIdArray = productIdArray || productId;

END IF;

END LOOP;

RETURN jsonb_build_object(
    'value',
    productIdArray,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartSubscriptionItemCount"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartSubscriptionItemCountFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartSubscriptionItemCountFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE subscriptionItemCount int;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'fact',
    'cartSubscriptionItemCount',
    'title',
    'Cart Subscription Item Count',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE
select
    "subscriptionItemCount" into subscriptionItemCount
from
    "subscription"."view_subscription"
where
    id = (
        select
            "subscriptionId"
        from
            "subscription"."subscriptionOccurence"
        where
            id = (
                select
                    "subscriptionOccurenceId"
                from
                    "order"."cart"
                where
                    id = (params ->> 'cartId') :: integer
            )
    );

RETURN jsonb_build_object(
    'value',
    subscriptionItemCount,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartSubscriptionServingSize"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartSubscriptionServingSizeFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartSubscriptionServingSizeFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE subscriptionServingSize int;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'fact',
    'cartSubscriptionServingSize',
    'title',
    'Subscription Serving Size',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE
select
    "subscriptionServingSize" into subscriptionServingSize
from
    "subscription"."view_subscription"
where
    id = (
        select
            "subscriptionId"
        from
            "subscription"."subscriptionOccurence"
        where
            id = (
                select
                    "subscriptionOccurenceId"
                from
                    "order"."cart"
                where
                    id = (params ->> 'cartId') :: integer
            )
    );

RETURN jsonb_build_object(
    'value',
    subscriptionServingSize,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartSubscriptionTitle"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."cartSubscriptionTitleFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."cartSubscriptionTitleFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE subscriptionTitle text;

operators text [] := ARRAY ['contains', 'doesNotContain', 'equal', 'notEqual'];

BEGIN IF (params ->> 'read') :: boolean = true THEN RETURN jsonb_build_object(
    'id',
    'cartSubscriptionTitle',
    'fact',
    'cartSubscriptionTitle',
    'title',
    'Subscription Title',
    'value',
    '{ "type" : "text" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE
select
    "title" into subscriptionTitle
from
    "subscription"."view_subscription"
where
    id = (
        select
            "subscriptionId"
        from
            "subscription"."subscriptionOccurence"
        where
            id = (
                select
                    "subscriptionOccurenceId"
                from
                    "order"."cart"
                where
                    id = (params ->> 'cartId') :: integer
            )
    );

RETURN jsonb_build_object(
    'value',
    subscriptionTitle,
    'valueType',
    'text',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."checkAllConditions"(conditionarray jsonb, params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $ function $ DECLARE condition jsonb;

res1 boolean := true;

res2 boolean := true;

res3 boolean := true;

tmp boolean := true;

BEGIN FOR condition IN
SELECT
    *
FROM
    jsonb_array_elements(conditionArray) LOOP IF condition -> 'all' IS NOT NULL THEN
SELECT
    rules."checkAllConditions"(condition -> 'all', params) INTO res2;

ELSIF condition -> 'any' IS NOT NULL THEN
SELECT
    rules."checkAnyConditions"(condition -> 'any', params) INTO res2;

ELSE
SELECT
    rules."assertFact"(condition :: jsonb, params) INTO tmp;

SELECT
    res3
    AND tmp INTO res3;

END IF;

END LOOP;

RETURN res1
AND res2
AND res3;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."checkAnyConditions"(conditionarray jsonb, params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $ function $ DECLARE condition jsonb;

res1 boolean := false;

res2 boolean := false;

res3 boolean := false;

tmp boolean := false;

BEGIN FOR condition IN
SELECT
    *
FROM
    jsonb_array_elements(conditionArray) LOOP IF condition -> 'all' IS NOT NULL THEN
SELECT
    rules."checkAllConditions"(condition -> 'all', params) INTO res2;

ELSIF condition -> 'any' IS NOT NULL THEN
SELECT
    rules."checkAnyConditions"(condition -> 'any', params) INTO res2;

ELSE
SELECT
    rules."assertFact"(condition :: jsonb, params) INTO tmp;

SELECT
    res3
    OR tmp INTO res3;

END IF;

END LOOP;

RETURN res1
OR res2
OR res3;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."customerEmail"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."customerEmailFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."customerEmailFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE customerEmail text;

operators text [] := ARRAY ['contains', 'doesNotContain', 'equal', 'notEqual'];

BEGIN IF params -> 'read' THEN RETURN jsonb_build_object(
    'id',
    'customerEmail',
    'fact',
    'customerEmail',
    'title',
    'Customer Email',
    'value',
    '{ "type" : "text" }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE
SELECT
    email
FROM
    crm."customer"
WHERE
    "keycloakId" = (params ->> 'keycloakId') :: text INTO customerEmail;

RETURN jsonb_build_object(
    'value',
    customerEmail,
    'valueType',
    'text',
    'argument',
    'keycloakId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."customerReferralCodeFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE referralCode text;

operators text [] := ARRAY ['contains', 'doesNotContain', 'equal', 'notEqual'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'customerReferralCode',
    'fact',
    'customerReferralCode',
    'title',
    'Customer Referral Code',
    'value',
    '{ "type" : "text" }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE
SELECT
    "referralCode"
FROM
    crm."customerReferral"
WHERE
    "keycloakId" = (params ->> 'keycloakId') :: text INTO referralCode;

RETURN json_build_object(
    'value',
    referralCode,
    'valueType',
    'text',
    'argument',
    'keycloakId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."customerReferredByCode"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."customerReferredByCodeFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."customerReferredByCodeFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE code text;

operators text [] := ARRAY ['equal', 'notEqual'];

BEGIN IF (params -> 'read') :: boolean = true THEN RETURN json_build_object(
    'id',
    'customerReferredByCode',
    'fact',
    'customerReferredByCode',
    'title',
    'Customer is Referred',
    'value',
    '{ "type" : "text" }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE
SELECT
    "referredByCode"
FROM
    crm."customerReferral"
WHERE
    "keycloakId" = (params ->> 'keycloakId') :: text
    AND "brandId" = (params ->> 'brandId') :: int INTO code;

IF code IS NULL THEN RETURN json_build_object(
    'value',
    'false',
    'valueType',
    'text',
    'argument',
    'keycloakId, brandId'
);

ELSE RETURN json_build_object(
    'value',
    'true',
    'valueType',
    'text',
    'argument',
    'keycloakId, brandId'
);

END IF;

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."customerReferrerCode"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."customerReferrerCodeFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."customerReferrerCodeFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE referredByCode text;

operators text [] := ARRAY ['contains', 'doesNotContain', 'equal', 'notEqual'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'customerReferrerCode',
    'fact',
    'customerReferrerCode',
    'title',
    'Customer Referrer Code',
    'value',
    '{ "type" : "text" }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE
SELECT
    "referredByCode"
FROM
    crm."customerReferral"
WHERE
    "keycloakId" = (params ->> 'keycloakId') :: text INTO referredByCode;

RETURN json_build_object(
    'value',
    referredByCode,
    'valueType',
    'text',
    'argument',
    'keycloakId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."customerSubscriptionSkipCountWithDuration"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."customerSubscriptionSkipCountWithDurationFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."customerSubscriptionSkipCountWithDurationFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE subscriptionSkipCount integer := 0;

enddate timestamp := current_timestamp;

startdate timestamp := enddate - (params ->> 'duration') :: interval;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'customerSubscriptionSkipCountWithDuration',
    'fact',
    'orderCountWithDuration',
    'title',
    'Order Count With Duration',
    'value',
    '{ "type" : "int", "duration" : true }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE
select
    count(*) into subscriptionSkipCount
from
    "subscription"."subscriptionOccurence_customer"
where
    "keycloakId" = (params ->> 'keycloakId') :: text
    and "isSkipped" = true
    and (
        "subscriptionOccurenceId" in (
            select
                "id"
            from
                "subscription"."subscriptionOccurence"
            where
                "fulfillmentDate" > startdate
                and "fulfillmentDate" < enddate
        )
    );

RETURN json_build_object(
    'value',
    subscriptionSkipCount,
    'valueType',
    'integer',
    'argument',
    'keycloakId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."getFactValue"(fact text, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ BEGIN RETURN call(
    'SELECT rules."' || fact || 'Func"' || '(' || '''' || params || '''' || ')'
);

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."isCartSubscription"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."isCartSubscriptionFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."isCartSubscriptionFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE cartSource text;

isSubscription text;

operators text [] := ARRAY ['equal', 'notEqual'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'fact',
    'isCartSubscription',
    'title',
    'is Cart from subscription',
    'value',
    '{ "type" : "text" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE
select
    "source" into cartSource
from
    "order"."cart"
where
    id = (params ->> 'cartId') :: integer;

if cartSource = 'subscription' then isSubscription := 'true';

else isSubscription := 'false';

end if;

RETURN jsonb_build_object(
    'value',
    isSubscription,
    'valueType',
    'boolean',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."isConditionValid"(condition rules.conditions, params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $ function $ DECLARE res boolean;

x int;

BEGIN
SELECT
    id
FROM
    crm.reward
WHERE
    "conditionId" = condition.id INTO x;

IF x IS NOT NULL THEN params := params || jsonb_build_object('rewardId', x);

END IF;

IF x IS NULL THEN
SELECT
    id
FROM
    crm.campaign
WHERE
    "conditionId" = condition.id INTO x;

IF x IS NOT NULL THEN params := params || jsonb_build_object('campaignId', x);

END IF;

END IF;

IF x IS NULL THEN
SELECT
    id
FROM
    crm.coupon
WHERE
    "visibleConditionId" = condition.id INTO x;

IF x IS NOT NULL THEN params := params || jsonb_build_object('couponId', x);

END IF;

END IF;

SELECT
    rules."isConditionValidFunc"(condition.id, params) INTO res;

RETURN res;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."isConditionValidFunc"(conditionid integer, params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $ function $ DECLARE res boolean;

condition record;

BEGIN
SELECT
    *
FROM
    rules.conditions
WHERE
    id = conditionId INTO condition;

IF condition.condition -> 'all' IS NOT NULL THEN
SELECT
    rules."checkAllConditions"(condition.condition -> 'all', params) INTO res;

ELSIF condition.condition -> 'any' IS NOT NULL THEN
SELECT
    rules."checkAnyConditions"(condition.condition -> 'any', params) INTO res;

ELSE
SELECT
    false INTO res;

END IF;

RETURN res;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."isCustomerReferred"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."isCustomerReferredFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."isCustomerReferredFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE referredByCode text;

value text := 'false';

operators text [] := ARRAY ['contains', 'doesNotContain', 'equal', 'notEqual'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'isCustomerReferred',
    'fact',
    'isCustomerReferred',
    'title',
    'Is Customer Referred',
    'value',
    '{ "type" : "text" }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE
SELECT
    "referredByCode"
FROM
    crm."customerReferral"
WHERE
    "keycloakId" = (params ->> 'keycloakId') :: text INTO referredByCode;

IF referredByCode is not null then value := 'true';

end if;

RETURN json_build_object(
    'value',
    value,
    'valueType',
    'text',
    'argument',
    'keycloakId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."numberOfCustomerReferred"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."numberOfCustomerReferredFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."numberOfCustomerReferredFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE referralCode text;

referredCount int;

value boolean := false;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'numberOfCustomerReferred',
    'fact',
    'numberOfCustomerReferred',
    'title',
    'Number Of Customer Referred',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE
SELECT
    "referralCode"
FROM
    crm."customerReferral"
WHERE
    "keycloakId" = (params ->> 'keycloakId') :: text INTO referralCode;

select
    count(*)
from
    crm."customerReferral"
WHERE
    "referredByCode" = referralCode INTO referredCount;

RETURN json_build_object(
    'value',
    referredCount,
    'valueType',
    'number',
    'argument',
    'keycloakId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."numberOfSubscriptionAddOnProducts"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."numberOfSubscriptionAddOnProductsFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."numberOfSubscriptionAddOnProductsFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE addedAddOnProductsCount int := 0;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'fact',
    'cartContainsAddOnProducts',
    'title',
    'Cart Contains AddOn Products',
    'operators',
    operators
);

ELSE
Select
    coalesce(COUNT(*), 0) INTO addedAddOnProductsCount
FROM
    "order"."cartItem"
WHERE
    "cartId" = (params ->> 'cartId') :: integer
    AND "isAddOn" = true
    AND "parentCartItemId" IS NULL;

RETURN jsonb_build_object(
    'value',
    addedAddOnProductsCount,
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."numberOfSuccessfulCustomerReferred"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."numberOfSuccessfulCustomerReferredFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."numberOfSuccessfulCustomerReferredFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE referralCode text;

referredCount int;

value boolean := false;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'numberOfSuccessfulCustomerReferred',
    'fact',
    'numberOfSuccessfulCustomerReferred',
    'title',
    'Number Of Customer Successfully Referred',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE
SELECT
    "referralCode"
FROM
    crm."customerReferral"
WHERE
    "keycloakId" = (params ->> 'keycloakId') :: text INTO referralCode;

select
    count(*)
from
    crm."customerReferral"
WHERE
    "referredByCode" = referralCode
    and "referralStatus" = 'COMPLETED' INTO referredCount;

RETURN json_build_object(
    'value',
    referredCount,
    'valueType',
    'number',
    'argument',
    'keycloakId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."orderCountWithDuration"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."orderCountWithDurationFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."orderCountWithDurationFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE dateArray timestamp [];

dateArr timestamp;

orderCount integer := 0;

enddate timestamp := current_timestamp;

startdate timestamp := enddate - (params ->> 'duration') :: interval;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'orderCountWithDuration',
    'fact',
    'orderCountWithDuration',
    'title',
    'Order Count With Duration',
    'value',
    '{ "type" : "int", "duration" : true }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE dateArray := ARRAY(
    SELECT
        "created_at"
    FROM
        "order"."cart"
    WHERE
        "customerKeycloakId" = (params ->> 'keycloakId') :: text
        AND "orderId" IS NOT NULL
);

FOREACH dateArr IN ARRAY dateArray LOOP IF dateArr > startdate
AND dateArr < enddate THEN orderCount := orderCount + 1;

END IF;

END LOOP;

RETURN json_build_object(
    'value',
    orderCount,
    'valueType',
    'integer',
    'argument',
    'keycloakId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."referralStatus"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."referralStatusFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."referralStatusFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE referralStatus text;

operators text [] := ARRAY ['equal', 'notEqual'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'referralStatus',
    'fact',
    'referralStatus',
    'title',
    'Customer Referral Status',
    'value',
    '{ "type" : "text" }' :: json,
    'argument',
    'keycloakId',
    'operators',
    operators
);

ELSE
SELECT
    "referralStatus"
FROM
    crm."customerReferral"
WHERE
    "keycloakId" = (params ->> 'keycloakId') :: text INTO referralStatus;

RETURN json_build_object(
    'value',
    referralStatus,
    'valueType',
    'text',
    'argument',
    'keycloakId'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."rruleHasDateFunc"(
    rrule _rrule.rruleset,
    d timestamp without time zone
) RETURNS boolean LANGUAGE plpgsql STABLE AS $ function $ DECLARE res boolean;

BEGIN
SELECT
    rrule @ > d into res;

RETURN res;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."runWithOperator"(operator text, vals jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $ function $ DECLARE res boolean := false;

BEGIN -- IF vals->>'fact' IS NOT NULL THEN
IF operator = 'rruleHasDate' THEN
SELECT
    rules."rruleHasDateFunc"(
        (vals -> 'condition') :: text :: jsonb :: _rrule.rruleset,
        (vals -> 'fact') :: text :: timestamp
    ) INTO res;

ELSIF operator = 'equal' THEN
SELECT
    (vals -> 'fact') :: text = (vals -> 'condition') :: text INTO res;

ELSIF operator = 'notEqual' THEN
SELECT
    (vals -> 'fact') :: text != (vals -> 'condition') :: text INTO res;

ELSIF operator = 'greaterThan' THEN
SELECT
    (vals ->> 'fact') :: numeric > (vals ->> 'condition') :: numeric INTO res;

ELSIF operator = 'greaterThanInclusive' THEN
SELECT
    (vals ->> 'fact') :: numeric >= (vals ->> 'condition') :: numeric INTO res;

ELSIF operator = 'lessThan' THEN
SELECT
    (vals ->> 'fact') :: numeric < (vals ->> 'condition') :: numeric INTO res;

ELSIF operator = 'lessThanInclusive' THEN
SELECT
    (vals ->> 'fact') :: numeric <= (vals ->> 'condition') :: numeric INTO res;

ELSIF operator = 'contains' THEN
SELECT
    vals ->> 'fact' LIKE CONCAT('%', vals ->> 'condition', '%') INTO res;

ELSIF operator = 'doesNotContain' THEN
SELECT
    vals ->> 'fact' NOT LIKE CONCAT('%', vals ->> 'condition', '%') INTO res;

ELSIF operator = 'in' THEN
SELECT
    vals ->> 'condition' = ANY(
        ARRAY(
            SELECT
                jsonb_array_elements_text(vals -> 'fact')
        )
    ) INTO res;

ELSIF operator = 'notIn' THEN
SELECT
    vals ->> 'condition' != ALL(
        ARRAY(
            SELECT
                jsonb_array_elements_text(vals -> 'fact')
        )
    ) INTO res;

ELSE
SELECT
    false INTO res;

END IF;

-- END IF;
RETURN res;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartComboProduct"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."totalNumberOfCartComboProductFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartComboProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartItem" record;

productType text;

productIdArray integer array DEFAULT '{}';

productId integer;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'totalNumberOfComboProducts',
    'fact',
    'totalNumberOfComboProducts',
    'title',
    'Total Number Of Combo Products (with Quantity)',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartItem" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
Select
    "type"
from
    "products"."product"
where
    "id" = "cartItem"."productId" into productType;

IF productType = 'combo' THEN
SELECT
    "cartItem"."productId" INTO productId;

productIdArray = productIdArray || productId;

END IF;

END LOOP;

RETURN json_build_object(
    'value',
    coalesce(array_length(productIdArray, 1), 0),
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartCustomizableProduct"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."totalNumberOfCartCustomizableProductFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartCustomizableProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartItem" record;

productType text;

productIdArray integer array DEFAULT '{}';

productId integer;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'totalNumberOfCustomizableProducts',
    'fact',
    'totalNumberOfCustomizableProducts',
    'title',
    'Total Number Of Customizable Products (with Quantity)',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartItem" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
Select
    "type"
from
    "products"."product"
where
    "id" = "cartItem"."productId" into productType;

IF productType = 'customizable' THEN
SELECT
    "cartItem"."productId" INTO productId;

productIdArray = productIdArray || productId;

END IF;

END LOOP;

RETURN json_build_object(
    'value',
    coalesce(array_length(productIdArray, 1), 0),
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartInventoryProduct"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."totalNumberOfCartInventoryProductFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartInventoryProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartProduct" record;

productOptionType text;

productOptionIdArray integer array DEFAULT '{}';

productOptionId integer;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'totalNumberOfInventoryProducts',
    'fact',
    'totalNumberOfInventoryProducts',
    'title',
    'Total Number Of Ready To Eat Products (with Quantity)',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartProduct" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
select
    "productOptionId"
from
    "order"."cartItem"
where
    "parentCartItemId" = "cartProduct"."id" into productOptionId;

SELECT
    "type"
from
    "products"."productOption"
where
    "id" = productOptionId into productOptionType;

IF productOptionType = 'inventory' then productOptionIdArray = productOptionIdArray || productOptionId;

END IF;

END LOOP;

RETURN json_build_object(
    'value',
    coalesce(array_length(productOptionIdArray, 1), 0),
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartMealKitProduct"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."totalNumberOfCartMealKitProductFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartMealKitProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartProduct" record;

productOptionType text;

productOptionIdArray integer array DEFAULT '{}';

productOptionId integer;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'totalNumberOfMealKitProducts',
    'fact',
    'totalNumberOfMealKitProducts',
    'title',
    'Total Number Of Meal Kit Products (with Quantity)',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartProduct" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
select
    "productOptionId"
from
    "order"."cartItem"
where
    "parentCartItemId" = "cartProduct"."id" into productOptionId;

SELECT
    "type"
from
    "products"."productOption"
where
    "id" = productOptionId into productOptionType;

IF productOptionType = 'mealKit' then productOptionIdArray = productOptionIdArray || productOptionId;

END IF;

END LOOP;

RETURN json_build_object(
    'value',
    coalesce(array_length(productOptionIdArray, 1), 0),
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartReadyToEatProduct"(fact rules.facts, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE result jsonb;

BEGIN
SELECT
    rules."totalNumberOfCartReadyToEatProductFunc"(params) INTO result;

RETURN result;

END;

$ function $;

CREATE
OR REPLACE FUNCTION rules."totalNumberOfCartReadyToEatProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ function $ DECLARE "cartProduct" record;

productOptionType text;

productOptionIdArray integer array DEFAULT '{}';

productOptionId integer;

operators text [] := ARRAY ['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];

BEGIN IF params -> 'read' THEN RETURN json_build_object(
    'id',
    'totalNumberOfReadyToEatProducts',
    'fact',
    'totalNumberOfReadyToEatProducts',
    'title',
    'Total Number Of Ready To Eat Products (with Quantity)',
    'value',
    '{ "type" : "int" }' :: json,
    'argument',
    'cartId',
    'operators',
    operators
);

ELSE FOR "cartProduct" IN
SELECT
    *
from
    "order"."cartItem"
where
    "cartId" = (params ->> 'cartId') :: integer LOOP
select
    "productOptionId"
from
    "order"."cartItem"
where
    "parentCartItemId" = "cartProduct"."id" into productOptionId;

SELECT
    "type"
from
    "products"."productOption"
where
    "id" = productOptionId into productOptionType;

IF productOptionType = 'readyToEat' then productOptionIdArray = productOptionIdArray || productOptionId;

END IF;

END LOOP;

RETURN json_build_object(
    'value',
    coalesce(array_length(productOptionIdArray, 1), 0),
    'valueType',
    'integer',
    'argument',
    'cartid'
);

END IF;

END;

$ function $;