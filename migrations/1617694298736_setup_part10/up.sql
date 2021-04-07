CREATE FUNCTION "order"."createSachets"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE inventorySachet "products"."inventoryProductBundleSachet";

sachet "simpleRecipe"."simpleRecipeYield_ingredientSachet";

counter int;

modifierOption record;

BEGIN IF NEW."simpleRecipeYieldId" IS NOT NULL THEN FOR sachet IN
SELECT
    *
FROM
    "simpleRecipe"."simpleRecipeYield_ingredientSachet"
WHERE
    "recipeYieldId" = NEW."simpleRecipeYieldId" LOOP IF sachet."ingredientSachetId" IS NOT NULL THEN
INSERT INTO
    "order"."cartItem"(
        "parentCartItemId",
        "ingredientSachetId",
        "cartId"
    )
VALUES
    (
        NEW.id,
        sachet."ingredientSachetId",
        NEW."cartId"
    );

ELSEIF sachet."subRecipeYieldId" IS NOT NULL THEN
INSERT INTO
    "order"."cartItem"("parentCartItemId", "subRecipeYieldId", "cartId")
VALUES
    (NEW.id, sachet."subRecipeYieldId", NEW."cartId");

END IF;

END LOOP;

ELSEIF NEW."inventoryProductBundleId" IS NOT NULL THEN FOR inventorySachet IN
SELECT
    *
FROM
    "products"."inventoryProductBundleSachet"
WHERE
    "inventoryProductBundleId" = NEW."inventoryProductBundleId" LOOP IF inventorySachet."sachetItemId" IS NOT NULL THEN
INSERT INTO
    "order"."cartItem"("parentCartItemId", "sachetItemId", "cartId")
VALUES
    (
        NEW.id,
        inventorySachet."sachetItemId",
        NEW."cartId"
    );

END IF;

END LOOP;

ELSEIF NEW."subRecipeYieldId" IS NOT NULL THEN FOR sachet IN
SELECT
    *
FROM
    "simpleRecipe"."simpleRecipeYield_ingredientSachet"
WHERE
    "recipeYieldId" = NEW."subRecipeYieldId" LOOP IF sachet."ingredientSachetId" IS NOT NULL THEN
INSERT INTO
    "order"."cartItem"(
        "parentCartItemId",
        "ingredientSachetId",
        "cartId"
    )
VALUES
    (
        NEW.id,
        sachet."ingredientSachetId",
        NEW."cartId"
    );

ELSEIF sachet."subRecipeYieldId" IS NOT NULL THEN
INSERT INTO
    "order"."cartItem"("parentCartItemId", "subRecipeYieldId", "cartId")
VALUES
    (NEW.id, sachet."subRecipeYieldId", NEW."cartId");

END IF;

END LOOP;

ELSEIF NEW."modifierOptionId" IS NOT NULL THEN
SELECT
    *
FROM
    "onDemand"."modifierCategoryOption"
WHERE
    id = NEW."modifierOptionId" INTO modifierOption;

counter := modifierOption.quantity;

IF modifierOption."sachetItemId" IS NOT NULL THEN WHILE counter >= 1 LOOP
INSERT INTO
    "order"."cartItem"("parentCartItemId", "sachetItemId", "cartId")
VALUES
    (
        NEW.id,
        modifierOption."sachetItemId",
        NEW."cartId"
    );

counter := counter - 1;

END LOOP;

ELSEIF modifierOption."simpleRecipeYieldId" IS NOT NULL THEN WHILE counter >= 1 LOOP
INSERT INTO
    "order"."cartItem"("parentCartItemId", "subRecipeYieldId", "cartId")
VALUES
    (
        NEW.id,
        modifierOption."simpleRecipeYieldId",
        NEW."cartId"
    );

counter := counter - 1;

END LOOP;

ELSEIF modifierOption."ingredientSachetId" IS NOT NULL THEN WHILE counter >= 1 LOOP
INSERT INTO
    "order"."cartItem"(
        "parentCartItemId",
        "ingredientSachetId",
        "cartId"
    )
VALUES
    (
        NEW.id,
        modifierOption."ingredientSachetId",
        NEW."cartId"
    );

counter := counter - 1;

END LOOP;

END IF;

END IF;

RETURN null;

END;

$ $;

CREATE FUNCTION "order"."deliveryPrice"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE value numeric;

total numeric;

rangeId int;

subscriptionId int;

price numeric := 0;

BEGIN IF cart."fulfillmentInfo" :: json ->> 'type' LIKE '%PICKUP'
OR cart."fulfillmentInfo" IS NULL THEN RETURN 0;

END IF;

IF cart."source" = 'a-la-carte' THEN
SELECT
    "order"."itemTotal"(cart) into total;

SELECT
    cart."fulfillmentInfo" :: json #>'{"slot","mileRangeId"}' as int into rangeId;
SELECT
    charge
from
    "fulfilment"."charge"
WHERE
    charge."mileRangeId" = rangeId
    AND total >= charge."orderValueFrom"
    AND total < charge."orderValueUpto" into value;

IF value IS NOT NULL THEN RETURN value;

END IF;

SELECT
    MAX(charge)
from
    "fulfilment"."charge"
WHERE
    charge."mileRangeId" = rangeId into value;

IF value IS NULL THEN RETURN 0;

ELSE RETURN value;

END IF;

ELSE
SELECT
    "subscriptionId"
FROM
    crm."brand_customer"
WHERE
    "brandId" = cart."brandId"
    AND "keycloakId" = cart."customerKeycloakId" INTO subscriptionId;

SELECT
    "deliveryPrice"
FROM
    subscription."subscription_zipcode"
WHERE
    "subscriptionId" = subscriptionId
    AND zipcode = cart.address ->> 'zipcode' INTO price;

RETURN COALESCE(price, 0);

END IF;

RETURN 0;

END $ $;

CREATE FUNCTION "order".discount(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE totalPrice numeric;

itemTotal numeric;

deliveryPrice numeric;

rewardIds int [];

rewardId int;

reward record;

discount numeric := 0;

BEGIN
SELECT
    "order"."itemTotal"(cart.*) into itemTotal;

SELECT
    "order"."deliveryPrice"(cart.*) into deliveryPrice;

totalPrice := ROUND(itemTotal + deliveryPrice, 2);

rewardIds := ARRAY(
    SELECT
        "rewardId"
    FROM
        "order"."cart_rewards"
    WHERE
        "cartId" = cart.id
);

FOREACH rewardId IN ARRAY rewardIds LOOP
SELECT
    *
FROM
    crm.reward
WHERE
    id = rewardId INTO reward;

IF reward."type" = 'Discount' THEN IF reward."rewardValue" ->> 'type' = 'conditional' THEN discount := totalPrice * (
    (reward."rewardValue" -> 'value' ->> 'percentage') :: numeric / 100
);

IF discount > (reward."rewardValue" -> 'value' ->> 'max') :: numeric THEN discount := (reward."rewardValue" -> 'value' ->> 'max') :: numeric;

END IF;

ELSIF reward."rewardValue" ->> 'type' = 'absolute' THEN discount := (reward."rewardValue" ->> 'value') :: numeric;

ELSE discount := 0;

END IF;

END IF;

END LOOP;

IF discount > totalPrice THEN discount := totalPrice;

END IF;

RETURN ROUND(discount, 2);

END;

$ $;

CREATE FUNCTION "order"."duplicateCartItem"(params jsonb) RETURNS SETOF public.response LANGUAGE plpgsql STABLE AS $ $ BEGIN PERFORM "order"."duplicateCartItemVolatile"(params);

RETURN QUERY
SELECT
    true AS success,
    'Item duplicated!' AS message;

END;

$ $;

CREATE FUNCTION "order"."duplicateCartItemVolatile"(params jsonb) RETURNS SETOF void LANGUAGE plpgsql AS $ $ DECLARE currentItem record;

item record;

parentCartItemId int;

BEGIN
SELECT
    *
FROM
    "order"."cartItem"
WHERE
    id = (params ->> 'cartItemId') :: int INTO item;

INSERT INTO
    "order"."cartItem"(
        "cartId",
        "parentCartItemId",
        "isModifier",
        "productId",
        "productOptionId",
        "comboProductComponentId",
        "customizableProductComponentId",
        "simpleRecipeYieldId",
        "sachetItemId",
        "unitPrice",
        "ingredientSachetId",
        "isAddOn",
        "addOnPrice",
        "inventoryProductBundleId",
        "modifierOptionId",
        "subRecipeYieldId"
    )
VALUES
    (
        item."cartId",
        (params ->> 'parentCartItemId') :: int,
        item."isModifier",
        item."productId",
        item."productOptionId",
        item."comboProductComponentId",
        item."customizableProductComponentId",
        item."simpleRecipeYieldId",
        item."sachetItemId",
        item."unitPrice",
        item."ingredientSachetId",
        item."isAddOn",
        item."addOnPrice",
        item."inventoryProductBundleId",
        item."modifierOptionId",
        item."subRecipeYieldId"
    ) RETURNING id INTO parentCartItemId;

FOR currentItem IN
SELECT
    *
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" = item.id LOOP IF currentItem."ingredientSachetId" IS NULL
    AND currentItem."sachetItemId" IS NULL
    AND currentItem."subRecipeYieldId" IS NULL THEN PERFORM "order"."duplicateCartItemVolatile"(
        jsonb_build_object(
            'cartItemId',
            currentItem.id,
            'parentCartItemId',
            parentCartItemId
        )
    );

END IF;

END LOOP;

END;

$ $;

CREATE FUNCTION "order"."handleProductOption"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE cart "order"."cart";

productOption products."productOption";

mode text;

validFor text;

counter int := 0;

sachet "simpleRecipe"."simpleRecipeYield_ingredientSachet";

BEGIN IF NEW."productOptionId" IS NULL THEN RETURN NULL;

END IF;

SELECT
    *
from
    "order"."cart"
WHERE
    id = NEW.cartId INTO cart;

IF cart."paymentStatus" = 'SUCCEEDED' THEN
SELECT
    * INTO productOption
FROM
    products."productOption"
WHERE
    id = NEW."productOptionId";

SELECT
    "orderMode" INTO mode
FROM
    products."productOptionType"
WHERE
    title = productOption."type";

SELECT
    "validWhen" INTO validFor
FROM
    "order"."orderMode"
WHERE
    title = mode;

IF validFor = 'recipe' THEN counter := productOption.quantity;

WHILE counter >= 1 LOOP
INSERT INTO
    "order"."cartItem"("parentCartItemId", "simpleRecipeYieldId")
VALUES
    (NEW.id, productOption."simpleRecipeYieldId") RETURNING id;

FOR sachet IN
SELECT
    *
FROM
    "simpleRecipe"."simpleRecipeYield_ingredientSachet"
WHERE
    "recipeYieldId" = productOption."simpleRecipeYieldId" LOOP
INSERT INTO
    "order"."cartItem"("parentCartItemId", "ingredientSachetId")
VALUES
    (id, sachet."ingredientSachetId");

END LOOP;

counter := counter - 1;

END LOOP;

ELSIF validFor = 'sachetItem' THEN counter := productOption.quantity;

WHILE counter >= 1 LOOP
INSERT INTO
    "order"."cartItem"("parentCartItemId", "sachetItemId")
VALUES
    (NEW.id, productOption."sachetItemId") RETURNING id;

counter := counter - 1;

END LOOP;

END IF;

END IF;

RETURN NULL;

END;

$ $;

CREATE FUNCTION "order"."handleSubscriberStatus"() RETURNS trigger LANGUAGE plpgsql AS $ $ BEGIN IF NEW."paymentStatus" = 'PENDING'
OR NEW."subscriptionOccurenceId" IS NULL THEN RETURN NULL;

END IF;

UPDATE
    crm."customer"
SET
    "isSubscriber" = true
WHERE
    "keycloakId" = NEW."customerKeycloakId";

UPDATE
    crm."brand_customer"
SET
    "isSubscriber" = true
WHERE
    "brandId" = NEW."brandId"
    AND "keycloakId" = NEW."customerKeycloakId";

RETURN NULL;

END;

$ $;

CREATE FUNCTION "order"."isCartValid"(cart "order".cart) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ _ $ DECLARE totalPrice numeric := 0;

res jsonb;

productsCount int := 0;

BEGIN
SELECT
    "order"."totalPrice"(cart.*) INTO totalPrice;

SELECT
    count(*) INTO productsCount
FROM
    "order"."cartItem"
WHERE
    "cartId" = cart.id;

IF productsCount = 0 THEN res := json_build_object('status', false, 'error', 'No items in cart!');

ELSIF cart."customerInfo" IS NULL
OR cart."customerInfo" ->> 'customerFirstName' IS NULL THEN res := json_build_object(
    'status',
    false,
    'error',
    'Basic customer details missing!'
);

ELSIF cart."fulfillmentInfo" IS NULL THEN res := json_build_object(
    'status',
    false,
    'error',
    'No fulfillment mode selected!'
);

ELSIF cart."fulfillmentInfo" IS NOT NULL
AND cart.status = 'PENDING' THEN
SELECT
    "order"."validateFulfillmentInfo"(cart."fulfillmentInfo", cart."brandId") INTO res;

IF (res ->> 'status') :: boolean = false THEN PERFORM "order"."clearFulfillmentInfo"(cart.id);

END IF;

ELSIF cart."address" IS NULL
AND cart."fulfillmentInfo" :: json ->> 'type' LIKE '%DELIVERY' THEN res := json_build_object(
    'status',
    false,
    'error',
    'No address selected for delivery!'
);

ELSIF totalPrice > 0
AND totalPrice <= 0.5 THEN res := json_build_object(
    'status',
    false,
    'error',
    'Transaction amount should be greater than $0.5!'
);

ELSE res := jsonb_build_object('status', true, 'error', '');

END IF;

RETURN res;

END $ _ $;

CREATE FUNCTION "order"."isTaxIncluded"(cart "order".cart) RETURNS boolean LANGUAGE plpgsql STABLE AS $ $ DECLARE subscriptionId int;

itemCountId int;

taxIncluded boolean;

BEGIN IF cart."subscriptionOccurenceId" IS NOT NULL THEN
SELECT
    "subscriptionId" INTO subscriptionId
FROM
    subscription."subscriptionOccurence"
WHERE
    id = cart."subscriptionOccurenceId";

SELECT
    "subscriptionItemCountId" INTO itemCountId
FROM
    subscription.subscription
WHERE
    id = subscriptionId;

SELECT
    "isTaxIncluded" INTO taxIncluded
FROM
    subscription."subscriptionItemCount"
WHERE
    id = itemCountId;

RETURN taxIncluded;

END IF;

RETURN false;

END;

$ $;

CREATE FUNCTION "order"."itemTotal"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE total numeric;

BEGIN
SELECT
    SUM("unitPrice") INTO total
FROM
    "order"."cartItem"
WHERE
    "cartId" = cart."id";

RETURN COALESCE(total, 0);

END;

$ $;

CREATE
OR REPLACE FUNCTION "order"."loyaltyPointsUsable"(cart "order".cart) RETURNS integer LANGUAGE plpgsql STABLE AS $ function $ DECLARE setting record;

temp record;

itemTotal numeric;

deliveryPrice numeric;

tax numeric;

discount numeric;

totalPrice numeric;

amount numeric;

rate numeric;

pointsUsable int := 0;

balance int;

BEGIN
SELECT
    *
FROM
    brands."storeSetting"
WHERE
    "identifier" = 'Loyalty Points Usage'
    AND "type" = 'rewards' INTO setting;

SELECT
    *
FROM
    brands."brand_storeSetting"
WHERE
    "storeSettingId" = setting.id
    AND "brandId" = cart."brandId" INTO temp;

IF temp IS NOT NULL THEN setting := temp;

END IF;

IF setting IS NULL THEN RETURN pointsUsable;

END IF;

SELECT
    "order"."totalPrice"(cart.*) into totalPrice;

totalPrice := ROUND(totalPrice - cart."walletAmountUsed", 2);

amount := ROUND(
    totalPrice * ((setting.value ->> 'percentage') :: float / 100)
);

IF amount > (setting.value ->> 'max') :: int THEN amount := (setting.value ->> 'max') :: int;

END IF;

SELECT
    crm."getLoyaltyPointsConversionRate"(cart."brandId") INTO rate;

pointsUsable = ROUND(amount / rate);

SELECT
    points
FROM
    crm."loyaltyPoint"
WHERE
    "keycloakId" = cart."customerKeycloakId"
    AND "brandId" = cart."brandId" INTO balance;

IF pointsUsable > balance THEN pointsUsable := balance;

END IF;

-- if usable changes after cart update, then update used points
IF cart."loyaltyPointsUsed" > pointsUsable THEN PERFORM crm."setLoyaltyPointsUsedInCart"(cart.id, pointsUsable);

END IF;

RETURN pointsUsable;

END;

$ function $;

CREATE FUNCTION "order"."onPaymentSuccess"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE cart "order"."cart";

tax numeric := 0;

itemTotal numeric := 0;

deliveryPrice numeric := 0;

totalPrice numeric := 0;

BEGIN IF (
    SELECT
        COUNT(*)
    FROM
        "order"."order"
    WHERE
        "cartId" = NEW."id"
) > 0 THEN RETURN NULL;

END IF;

IF NEW."paymentStatus" != 'PENDING' THEN
SELECT
    *
from
    "order"."cart"
WHERE
    id = NEW.id INTO cart;

SELECT
    "order"."itemTotal"(cart.*) INTO itemTotal;

SELECT
    "order"."tax"(cart.*) INTO tax;

SELECT
    "order"."deliveryPrice"(cart.*) INTO deliveryPrice;

SELECT
    "order"."totalPrice"(cart.*) INTO totalPrice;

INSERT INTO
    "order"."order"(
        "cartId",
        "tip",
        "tax",
        "itemTotal",
        "deliveryPrice",
        "fulfillmentType",
        "amountPaid",
        "keycloakId",
        "brandId"
    )
VALUES
    (
        NEW.id,
        NEW.tip,
        tax,
        itemTotal,
        deliveryPrice,
        NEW."fulfillmentInfo" ->> 'type',
        totalPrice,
        NEW."customerKeycloakId",
        NEW."brandId"
    );

UPDATE
    "order"."cart"
SET
    "orderId" = (
        SELECT
            id
        FROM
            "order"."order"
        WHERE
            "cartId" = NEW.id
    ),
    status = 'ORDER_PENDING'
WHERE
    id = NEW.id;

END IF;

RETURN NULL;

END;

$ $;

CREATE FUNCTION "order".on_cart_item_status_change() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE totalReady integer := 0;

totalPacked integer := 0;

totalItems integer := 0;

BEGIN IF NEW.status = OLD.status THEN RETURN NULL;

END IF;

-- mark children packed if parent ready/packed
IF NEW.status = 'READY'
OR NEW.status = 'PACKED' THEN
UPDATE
    "order"."cartItem"
SET
    status = 'PACKED'
WHERE
    "parentCartItemId" = NEW.id;

END IF;

IF NEW.status = 'READY_FOR_PACKING'
OR NEW.status = 'READY' THEN IF NEW."parentCartItemId" IS NULL THEN
UPDATE
    "order"."cartItem"
SET
    status = 'PACKED'
WHERE
    id = NEW.id;

-- product
ELSEIF (
    SELECT
        "parentCartItemId"
    FROM
        "order"."cartItem"
    WHERE
        id = NEW."parentCartItemId"
) IS NULL THEN
UPDATE
    "order"."cartItem"
SET
    status = 'PACKED'
WHERE
    id = NEW.id;

-- productComponent
END IF;

END IF;

IF NEW.status = 'READY' THEN
SELECT
    COUNT(*) INTO totalReady
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" = NEW."parentCartItemId"
    AND status = 'READY';

SELECT
    COUNT(*) INTO totalItems
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" = NEW."parentCartItemId";

IF totalReady = totalItems THEN
UPDATE
    "order"."cartItem"
SET
    status = 'READY_FOR_PACKING'
WHERE
    id = NEW."parentCartItemId";

END IF;

END IF;

IF NEW.status = 'PACKED' THEN
SELECT
    COUNT(*) INTO totalPacked
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" = NEW."parentCartItemId"
    AND status = 'PACKED';

SELECT
    COUNT(*) INTO totalItems
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" = NEW."parentCartItemId";

IF totalPacked = totalItems THEN
UPDATE
    "order"."cartItem"
SET
    status = 'READY'
WHERE
    id = NEW."parentCartItemId"
    AND status = 'PENDING';

END IF;

END IF;

-- check order item status
IF (
    SELECT
        status
    FROM
        "order".cart
    WHERE
        id = NEW."cartId"
) = 'ORDER_PENDING' THEN
UPDATE
    "order".cart
SET
    status = 'ORDER_UNDER_PROCESSING'
WHERE
    id = NEW."cartId";

END IF;

IF NEW."parentCartItemId" IS NOT NULL THEN RETURN NULL;

END IF;

SELECT
    COUNT(*) INTO totalReady
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" IS NULL
    AND "cartId" = NEW."cartId"
    AND status = 'READY';

SELECT
    COUNT(*) INTO totalPacked
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" IS NULL
    AND "cartId" = NEW."cartId"
    AND status = 'PACKED';

SELECT
    COUNT(*) INTO totalItems
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" IS NULL
    AND "cartId" = NEW."cartId";

IF totalReady = totalItems THEN
UPDATE
    "order".cart
SET
    status = 'ORDER_READY_TO_ASSEMBLE'
WHERE
    id = NEW."cartId";

ELSEIF totalPacked = totalItems THEN
UPDATE
    "order".cart
SET
    status = 'ORDER_READY_TO_DISPATCH'
WHERE
    id = NEW."cartId";

END IF;

RETURN NULL;

END;

$ $;

CREATE FUNCTION "order".on_cart_status_change() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE item "order"."cartItem";

packedCount integer := 0;

readyCount integer := 0;

BEGIN IF OLD.status = NEW.status THEN RETURN NULL;

END IF;

IF NEW.status = 'ORDER_READY_TO_ASSEMBLE' THEN FOR item IN
SELECT
    *
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" IS NULL
    AND "cartId" = NEW.id LOOP
UPDATE
    "order"."cartItem"
SET
    status = 'READY'
WHERE
    id = item.id;

END LOOP;

ELSEIF NEW.status = 'ORDER_READY_FOR_DISPATCH' THEN FOR item IN
SELECT
    *
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" IS NULL
    AND "cartId" = NEW.id LOOP
UPDATE
    "order"."cartItem"
SET
    status = 'PACKED'
WHERE
    id = item.id;

END LOOP;

ELSEIF NEW.status = 'ORDER_OUT_FOR_DELIVERY'
OR NEW.status = 'ORDER_DELIVERED' THEN FOR item IN
SELECT
    *
FROM
    "order"."cartItem"
WHERE
    "parentCartItemId" IS NULL
    AND "cartId" = NEW.id LOOP
UPDATE
    "order"."cartItem"
SET
    status = 'PACKED'
WHERE
    id = item.id;

END LOOP;

END IF;

RETURN NULL;

END;

$ $;

CREATE FUNCTION "order".ordersummary(order_row "order"."order") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE counts jsonb;

amounts jsonb;

BEGIN
SELECT
    json_object_agg(each."orderStatus", each."count")
FROM
    (
        SELECT
            "orderStatus",
            COUNT (*)
        FROM
            "order"."order"
        GROUP BY
            "orderStatus"
    ) AS each into counts;

SELECT
    json_object_agg(each."orderStatus", each."total")
FROM
    (
        SELECT
            "orderStatus",
            SUM ("itemTotal") as total
        FROM
            "order"."order"
        GROUP BY
            "orderStatus"
    ) AS each into amounts;

RETURN json_build_object('count', counts, 'amount', amounts);

END $ $;

CREATE FUNCTION "order".set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE FUNCTION "order"."subTotal"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE amount numeric := 0;

discount numeric := 0;

itemTotal numeric;

deliveryPrice numeric;

BEGIN
SELECT
    "order"."itemTotal"(cart.*) into itemTotal;

SELECT
    "order"."deliveryPrice"(cart.*) into deliveryPrice;

SELECT
    "order".discount(cart.*) into discount;

amount := itemTotal + deliveryPrice + cart.tip - discount;

RETURN amount;

END $ $;

CREATE FUNCTION "order".tax(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE taxAmount numeric := 0;

amount numeric := 0;

tax numeric;

isTaxIncluded boolean;

BEGIN
SELECT
    "order"."isTaxIncluded"(cart.*) INTO isTaxIncluded;

SELECT
    "order"."subTotal"(cart.*) into amount;

SELECT
    "order"."taxPercent"(cart.*) into tax;

IF isTaxIncluded = true THEN RETURN ROUND((tax * amount) /(100 + tax), 2);

END IF;

RETURN ROUND(amount * (tax / 100), 2);

END;

$ $;

CREATE FUNCTION "order"."taxPercent"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE taxPercent numeric := 0;

percentage jsonb;

subscriptionId int;

itemCountId int;

BEGIN IF cart."subscriptionOccurenceId" IS NOT NULL THEN
SELECT
    "subscriptionId" INTO subscriptionId
FROM
    subscription."subscriptionOccurence"
WHERE
    id = cart."subscriptionOccurenceId";

SELECT
    "subscriptionItemCountId" INTO itemCountId
FROM
    subscription.subscription
WHERE
    id = subscriptionId;

SELECT
    "tax" INTO taxPercent
FROM
    subscription."subscriptionItemCount"
WHERE
    id = itemCountId;

RETURN taxPercent;

ELSEIF cart."subscriptionOccurenceId" IS NULL THEN
SELECT
    value
FROM
    brands."brand_storeSetting"
WHERE
    "brandId" = cart."brandId"
    AND "storeSettingId" = (
        SELECT
            id
        FROM
            brands."storeSetting"
        WHERE
            identifier = 'Tax Percentage'
    ) INTO percentage;

RETURN (percentage ->> 'value') :: numeric;

ELSE RETURN 2.5;

END IF;

END;

$ $;

CREATE FUNCTION "order"."totalPrice"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE totalPrice numeric;

tax numeric;

rate numeric;

loyaltyPointsAmount numeric := 0;

subTotal numeric;

isTaxIncluded boolean;

BEGIN
SELECT
    "order"."subTotal"(cart.*) INTO subTotal;

SELECT
    "order".tax(cart.*) into tax;

SELECT
    "order"."isTaxIncluded"(cart.*) INTO isTaxIncluded;

IF cart."loyaltyPointsUsed" > 0 THEN
SELECT
    crm."getLoyaltyPointsConversionRate"(cart."brandId") INTO rate;

loyaltyPointsAmount := ROUND(rate * cart."loyaltyPointsUsed", 2);

END IF;

IF isTaxIncluded = true THEN totalPrice := ROUND(
    subTotal - COALESCE(cart."walletAmountUsed", 0) - loyaltyPointsAmount,
    2
);

ELSE totalPrice := ROUND(
    subTotal - COALESCE(cart."walletAmountUsed", 0) - loyaltyPointsAmount + tax,
    2
);

END IF;

RETURN totalPrice;

END $ $;

CREATE FUNCTION "order"."updateStatementDescriptor"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE setting jsonb;

statementDescriptor text := 'food order';

BEGIN IF NEW.source = 'a-la-carte' then
SELECT
    "value"
from
    "brands"."brand_storeSetting"
where
    "brandId" = NEW."brandId"
    and "storeSettingId" = (
        select
            id
        from
            "brands"."storeSetting"
        where
            "identifier" = 'Statement Descriptor'
    ) into setting;

ELSIF NEW.source = 'subscription' then
SELECT
    "value"
from
    "brands"."brand_subscriptionStoreSetting"
where
    "brandId" = NEW."brandId"
    and "subscriptionStoreSettingId" = (
        select
            id
        from
            "brands"."subscriptionStoreSetting"
        where
            "identifier" = 'Statement Descriptor'
    ) into setting;

END IF;

UPDATE
    "order"."cart"
SET
    "statementDescriptor" = setting ->> 'value'
where
    id = NEW.id;

RETURN NULL;

END;

$ $;

CREATE FUNCTION "order"."validateFulfillmentInfo"(f jsonb, brandidparam integer) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE res jsonb;

recurrence record;

timeslot record;

slotFrom time;

slotUpto time;

slotDate timestamp;

isValid boolean;

err text := '';

BEGIN IF (f -> 'slot' ->> 'from') :: timestamp > NOW() :: timestamp THEN IF f ->> 'type' = 'ONDEMAND_DELIVERY' THEN -- FOR recurrence IN SELECT * FROM fulfilment.recurrence WHERE "type" = 'ONDEMAND_DELIVERY' LOOP
--     IF recurrence.psql_rrule::_rrule.rruleset @> NOW()::TIMESTAMP WITHOUT TIME ZONE THEN
--         FOR timeslot IN SELECT * FROM fulfilment."timeSlot" WHERE "recurrenceId" = recurrence.id LOOP
--             IF timeslot."from" < CURRENT_TIME AND timeslot."to" > CURRENT_TIME THEN
--                 res := json_build_object('status', true, 'error', 'Valid date and time!');
--             ELSE
--                 res := json_build_object('status', false, 'error', 'Invalid time!');
--             END IF;
--         END LOOP;
--     ELSE
--         res := json_build_object('status', false, 'error', 'Invalid date!');    
--     END IF;
-- END LOOP;
SELECT
    *
FROM
    fulfilment."timeSlot"
WHERE
    id = (
        SELECT
            "timeSlotId"
        FROM
            fulfilment."mileRange"
        WHERE
            id = (f -> 'slot' ->> 'mileRangeId') :: int
            AND "isActive" = true
    )
    AND "isActive" = true INTO timeslot;

IF timeslot."from" < CURRENT_TIME
AND timeslot."to" > CURRENT_TIME THEN
SELECT
    *
FROM
    fulfilment.recurrence
WHERE
    id = timeslot."recurrenceId"
    AND "isActive" = true INTO recurrence;

IF recurrence IS NOT NULL
AND recurrence.psql_rrule :: _rrule.rruleset @ > NOW() :: TIMESTAMP WITHOUT TIME ZONE THEN res := json_build_object('status', true, 'error', 'Valid date and time!');

ELSE res := json_build_object('status', false, 'error', 'Invalid date!');

END IF;

ELSE res := json_build_object('status', false, 'error', 'Invalid time!');

END IF;

ELSIF f ->> 'type' = 'PREORDER_DELIVERY' THEN slotFrom := substring(f -> 'slot' ->> 'from', 12, 8) :: time;

slotUpto := substring(f -> 'slot' ->> 'to', 12, 8) :: time;

slotDate := substring(f -> 'slot' ->> 'from', 0, 11) :: timestamp;

SELECT
    *
FROM
    fulfilment."timeSlot"
WHERE
    id = (
        SELECT
            "timeSlotId"
        FROM
            fulfilment."mileRange"
        WHERE
            id = (f -> 'slot' ->> 'mileRangeId') :: int
            AND "isActive" = true
    )
    AND "isActive" = true INTO timeslot;

IF timeslot."from" < slotFrom
AND timeslot."to" > slotFrom THEN -- lead time is already included in the slot (front-end)
SELECT
    *
FROM
    fulfilment.recurrence
WHERE
    id = timeslot."recurrenceId"
    AND "isActive" = true INTO recurrence;

IF recurrence IS NOT NULL
AND recurrence.psql_rrule :: _rrule.rruleset @ > slotDate THEN res := json_build_object('status', true, 'error', 'Valid date and time!');

ELSE res := json_build_object('status', false, 'error', 'Invalid date!');

END IF;

ELSE res := json_build_object('status', false, 'error', 'Invalid time!');

END IF;

ELSIF f ->> 'type' = 'ONDEMAND_PICKUP' THEN slotFrom := substring(f -> 'slot' ->> 'from', 12, 8) :: time;

slotUpto := substring(f -> 'slot' ->> 'to', 12, 8) :: time;

slotDate := substring(f -> 'slot' ->> 'from', 0, 11) :: timestamp;

isValid := false;

FOR recurrence IN
SELECT
    *
FROM
    fulfilment.recurrence
WHERE
    "type" = 'ONDEMAND_PICKUP'
    AND "isActive" = true
    AND id IN (
        SELECT
            "recurrenceId"
        FROM
            fulfilment.brand_recurrence
        WHERE
            "brandId" = brandIdParam
    ) LOOP IF recurrence.psql_rrule :: _rrule.rruleset @ > NOW() :: TIMESTAMP WITHOUT TIME ZONE THEN FOR timeslot IN
SELECT
    *
FROM
    fulfilment."timeSlot"
WHERE
    "recurrenceId" = recurrence.id
    AND "isActive" = true LOOP IF timeslot."from" < slotFrom
    AND timeslot."to" > slotFrom THEN isValid := true;

EXIT;

END IF;

END LOOP;

IF isValid = false THEN err := 'No time slot available!';

END IF;

END IF;

END LOOP;

res := json_build_object('status', isValid, 'error', err);

ELSE slotFrom := substring(f -> 'slot' ->> 'from', 12, 8) :: time;

slotUpto := substring(f -> 'slot' ->> 'to', 12, 8) :: time;

slotDate := substring(f -> 'slot' ->> 'from', 0, 11) :: timestamp;

isValid := false;

FOR recurrence IN
SELECT
    *
FROM
    fulfilment.recurrence
WHERE
    "type" = 'PREORDER_PICKUP'
    AND "isActive" = true
    AND id IN (
        SELECT
            "recurrenceId"
        FROM
            fulfilment.brand_recurrence
        WHERE
            "brandId" = brandIdParam
    ) LOOP IF recurrence.psql_rrule :: _rrule.rruleset @ > slotDate THEN FOR timeslot IN
SELECT
    *
FROM
    fulfilment."timeSlot"
WHERE
    "recurrenceId" = recurrence.id
    AND "isActive" = true LOOP IF timeslot."from" < slotFrom
    AND timeslot."to" > slotFrom THEN isValid := true;

EXIT;

END IF;

END LOOP;

IF isValid = false THEN err := 'No time slot available!';

END IF;

END IF;

END LOOP;

res := json_build_object('status', isValid, 'error', err);

END IF;

ELSE res := jsonb_build_object('status', false, 'error', 'Slot expired!');

END IF;

res := res || jsonb_build_object('type', 'fulfillment');

RETURN res;

END $ $;

CREATE
OR REPLACE FUNCTION "order"."walletAmountUsable"(cart "order".cart) RETURNS numeric LANGUAGE plpgsql STABLE AS $ function $ DECLARE setting record;

temp record;

itemTotal numeric;

deliveryPrice numeric;

tax numeric;

discount numeric;

totalPrice numeric;

rate numeric;

pointsAmount numeric := 0;

amountUsable numeric := 0;

balance numeric;

BEGIN
SELECT
    *
FROM
    brands."storeSetting"
WHERE
    "identifier" = 'Loyalty Points Usage'
    AND "type" = 'rewards' INTO setting;

SELECT
    *
FROM
    brands."brand_storeSetting"
WHERE
    "storeSettingId" = setting.id
    AND "brandId" = cart."brandId" INTO temp;

IF temp IS NOT NULL THEN setting := temp;

END IF;

SELECT
    "order"."totalPrice"(cart.*) into totalPrice;

amountUsable := totalPrice;

-- if loyalty points are used
IF cart."loyaltyPointsUsed" > 0 THEN
SELECT
    crm."getLoyaltyPointsConversionRate"(cart."brandId") INTO rate;

pointsAmount := rate * cart."loyaltyPointsUsed";

amountUsable := amountUsable - pointsAmount;

END IF;

SELECT
    amount
FROM
    crm."wallet"
WHERE
    "keycloakId" = cart."customerKeycloakId"
    AND "brandId" = cart."brandId" INTO balance;

IF amountUsable > balance THEN amountUsable := balance;

END IF;

-- if usable changes after cart update, then update used amount
IF cart."walletAmountUsed" > amountUsable THEN PERFORM crm."setWalletAmountUsedInCart"(cart.id, amountUsable);

END IF;

RETURN amountUsable;

END;

$ function $;

CREATE VIEW products."customizableComponentOptions" AS
SELECT
    t.id AS "customizableComponentId",
    t."linkedProductId",
    ((option.value ->> 'optionId' :: text)) :: integer AS "productOptionId",
    ((option.value ->> 'price' :: text)) :: numeric AS price,
    ((option.value ->> 'discount' :: text)) :: numeric AS discount,
    t."productId"
FROM
    products."customizableProductComponent" t,
    LATERAL jsonb_array_elements(t.options) option(value);

CREATE FUNCTION products."comboProductComponentCustomizableCartItem"(
    componentoption products."customizableComponentOptions"
) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE counter int;

items jsonb [] := '{}';

product record;

option record;

BEGIN
SELECT
    *
FROM
    products.product
WHERE
    id = componentOption."productId" INTO product;

SELECT
    *
FROM
    products."productOption"
WHERE
    id = componentOption."productOptionId" INTO option;

counter := option.quantity;

IF option."simpleRecipeYieldId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'simpleRecipeYieldId',
    option."simpleRecipeYieldId"
) :: jsonb;

counter := counter - 1;

END LOOP;

ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'inventoryProductBundleId',
    option."inventoryProductBundleId"
) :: jsonb;

counter := counter - 1;

END LOOP;

END IF;

RETURN jsonb_build_object(
    'customizableProductComponentId',
    componentOption."customizableComponentId",
    'productOptionId',
    componentOption."productOptionId",
    'unitPrice',
    componentOption.price,
    'childs',
    json_build_object('data', items)
);

END;

$ $;

CREATE FUNCTION products."comboProductComponentFullName"(component products."comboProductComponent") RETURNS text LANGUAGE plpgsql STABLE AS $ $ DECLARE productName text;

childProductName text;

BEGIN
SELECT
    name
FROM
    products.product
WHERE
    id = component."productId" INTO productName;

SELECT
    name
FROM
    products.product
WHERE
    id = component."linkedProductId" INTO childProductName;

RETURN productName || ' - ' || childProductName || '(' || component.label || ')';

END;

$ $;

CREATE VIEW products."comboComponentOptions" AS
SELECT
    t.id AS "comboComponentId",
    t."linkedProductId",
    ((option.value ->> 'optionId' :: text)) :: integer AS "productOptionId",
    ((option.value ->> 'price' :: text)) :: numeric AS price,
    ((option.value ->> 'discount' :: text)) :: numeric AS discount,
    t."productId"
FROM
    products."comboProductComponent" t,
    LATERAL jsonb_array_elements(t.options) option(value);

CREATE FUNCTION products."comboProductComponentOptionCartItem"(componentoption products."comboComponentOptions") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE counter int;

items jsonb [] := '{}';

product record;

option record;

BEGIN
SELECT
    *
FROM
    products.product
WHERE
    id = componentOption."productId" INTO product;

SELECT
    *
FROM
    products."productOption"
WHERE
    id = componentOption."productOptionId" INTO option;

counter := option.quantity;

IF option."simpleRecipeYieldId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'simpleRecipeYieldId',
    option."simpleRecipeYieldId"
) :: jsonb;

counter := counter - 1;

END LOOP;

ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'inventoryProductBundleId',
    option."inventoryProductBundleId"
) :: jsonb;

counter := counter - 1;

END LOOP;

END IF;

RETURN jsonb_build_object(
    'comboProductComponentId',
    componentOption."comboComponentId",
    'productOptionId',
    componentOption."productOptionId",
    'unitPrice',
    componentOption.price,
    'childs',
    json_build_object('data', items)
);

END;

$ $;

CREATE FUNCTION products."customizableProductComponentFullName"(
    component products."customizableProductComponent"
) RETURNS text LANGUAGE plpgsql STABLE AS $ $ DECLARE productName text;

childProductName text;

BEGIN
SELECT
    name
FROM
    products.product
WHERE
    id = component."productId" INTO productName;

SELECT
    name
FROM
    products.product
WHERE
    id = component."linkedProductId" INTO childProductName;

RETURN productName || ' - ' || childProductName;

END;

$ $;

CREATE FUNCTION products."customizableProductComponentOptionCartItem"(
    componentoption products."customizableComponentOptions"
) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE counter int;

items jsonb [] := '{}';

product record;

option record;

BEGIN
SELECT
    *
FROM
    products.product
WHERE
    id = componentOption."productId" INTO product;

SELECT
    *
FROM
    products."productOption"
WHERE
    id = componentOption."productOptionId" INTO option;

counter := option.quantity;

IF option."simpleRecipeYieldId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'simpleRecipeYieldId',
    option."simpleRecipeYieldId"
) :: jsonb;

counter := counter - 1;

END LOOP;

ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'inventoryProductBundleId',
    option."inventoryProductBundleId"
) :: jsonb;

counter := counter - 1;

END LOOP;

END IF;

RETURN jsonb_build_object(
    'productId',
    product.id,
    'unitPrice',
    product.price,
    'childs',
    jsonb_build_object(
        'data',
        json_build_array(
            json_build_object (
                'customizableProductComponentId',
                componentOption."customizableComponentId",
                'productOptionId',
                componentOption."productOptionId",
                'unitPrice',
                componentOption.price,
                'childs',
                json_build_object(
                    'data',
                    items
                )
            )
        )
    )
);

END;

$ $;

CREATE FUNCTION products."getProductType"(pid integer) RETURNS text LANGUAGE plpgsql STABLE AS $ $ DECLARE productOption record;

comboComponentsCount int;

customizableOptionsCount int;

BEGIN
SELECT
    *
FROM
    products."productOption"
WHERE
    id = pId INTO productOption
LIMIT
    1;

SELECT
    COUNT(*)
FROM
    products."customizableProductOption"
WHERE
    "productId" = pId INTO customizableOptionsCount;

SELECT
    COUNT(*)
FROM
    products."comboProductComponent"
WHERE
    "productId" = pId INTO comboComponentsCount;

IF productOption."sachetItemId" IS NOT NULL
OR productOption."supplierItemId" IS NOT NULL THEN RETURN 'inventoryProduct';

ELSIF productOption."simpleRecipeYieldId" IS NOT NULL THEN RETURN 'simpleRecipeProduct';

ELSEIF customizableOptionsCount > 0 THEN RETURN 'customizableProduct';

ELSEIF comboComponentsCount > 0 THEN RETURN 'comboProduct';

ELSE RETURN 'none';

END IF;

END;

$ $;

CREATE FUNCTION products."isProductValid"(product products.product) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE component record;

isValid boolean := true;

message text := '';

counter int := 0;

BEGIN RETURN jsonb_build_object('status', isValid, 'error', message);

END $ $;

CREATE FUNCTION products."productCartItemById"(optionid integer) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE counter int;

items jsonb [] := '{}';

option products."productOption";

product products."product";

BEGIN
SELECT
    * INTO option
FROM
    products."productOption"
WHERE
    id = optionId;

SELECT
    *
FROM
    products.product
WHERE
    id = option."productId" INTO product;

counter := option.quantity;

IF option."simpleRecipeYieldId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'simpleRecipeYieldId',
    option."simpleRecipeYieldId"
) :: jsonb;

counter := counter - 1;

END LOOP;

ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'inventoryProductBundleId',
    option."inventoryProductBundleId"
) :: jsonb;

counter := counter - 1;

END LOOP;

END IF;

RETURN json_build_object(
    'productId',
    product.id,
    'childs',
    jsonb_build_object(
        'data',
        json_build_array(
            json_build_object (
                'productOptionId',
                option.id,
                'unitPrice',
                0,
                'childs',
                json_build_object(
                    'data',
                    items
                )
            )
        )
    )
);

END $ $;

CREATE FUNCTION products."productOptionCartItem"(option products."productOption") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE counter int;

items jsonb [] := '{}';

product products."product";

BEGIN
SELECT
    *
FROM
    products.product
WHERE
    id = option."productId" INTO product;

counter := option.quantity;

IF option."simpleRecipeYieldId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'simpleRecipeYieldId',
    option."simpleRecipeYieldId"
) :: jsonb;

counter := counter - 1;

END LOOP;

ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN WHILE counter >= 1 LOOP items := items || json_build_object(
    'inventoryProductBundleId',
    option."inventoryProductBundleId"
) :: jsonb;

counter := counter - 1;

END LOOP;

END IF;

RETURN json_build_object(
    'productId',
    product.id,
    'unitPrice',
    product.price,
    'childs',
    jsonb_build_object(
        'data',
        json_build_array(
            json_build_object (
                'productOptionId',
                option.id,
                'unitPrice',
                option.price,
                'childs',
                json_build_object(
                    'data',
                    items
                )
            )
        )
    )
);

END;

$ $;

CREATE VIEW products."productOptionView" AS
SELECT
    "productOption".id,
    "productOption"."productId",
    "productOption".label,
    "productOption"."modifierId",
    "productOption"."operationConfigId",
    "productOption"."simpleRecipeYieldId",
    "productOption"."supplierItemId",
    "productOption"."sachetItemId",
    "productOption"."position",
    "productOption".created_at,
    "productOption".updated_at,
    "productOption".price,
    "productOption".discount,
    "productOption".quantity,
    "productOption".type,
    "productOption"."isArchived",
    "productOption"."inventoryProductBundleId",
    btrim(
        concat(
            (
                SELECT
                    product.name
                FROM
                    products.product
                WHERE
                    (product.id = "productOption"."productId")
            ),
            ' - ',
            "productOption".label
        )
    ) AS "displayName",
    (
        SELECT
            ((product.assets -> 'images' :: text) -> 0)
        FROM
            products.product
        WHERE
            (product.id = "productOption"."productId")
    ) AS "displayImage"
FROM
    products."productOption";

CREATE VIEW "simpleRecipe"."simpleRecipeYieldView" AS
SELECT
    "simpleRecipeYield".id,
    "simpleRecipeYield"."simpleRecipeId",
    "simpleRecipeYield".yield,
    "simpleRecipeYield"."isArchived",
    (
        (
            SELECT
                "simpleRecipe".name
            FROM
                "simpleRecipe"."simpleRecipe"
            WHERE
                (
                    "simpleRecipe".id = "simpleRecipeYield"."simpleRecipeId"
                )
        )
    ) :: text AS "displayName",
    (("simpleRecipeYield".yield -> 'serving' :: text)) :: integer AS serving
FROM
    "simpleRecipe"."simpleRecipeYield";

CREATE VIEW "order"."cartItemView" AS WITH RECURSIVE parent AS (
    SELECT
        "cartItem".id,
        "cartItem"."cartId",
        "cartItem"."parentCartItemId",
        "cartItem"."isModifier",
        "cartItem"."productId",
        "cartItem"."productOptionId",
        "cartItem"."comboProductComponentId",
        "cartItem"."customizableProductComponentId",
        "cartItem"."simpleRecipeYieldId",
        "cartItem"."sachetItemId",
        "cartItem"."subRecipeYieldId",
        "cartItem"."isAssembled",
        "cartItem"."unitPrice",
        "cartItem"."refundPrice",
        "cartItem"."stationId",
        "cartItem"."labelTemplateId",
        "cartItem"."packagingId",
        "cartItem"."instructionCardTemplateId",
        "cartItem"."assemblyStatus",
        "cartItem"."position",
        "cartItem".created_at,
        "cartItem".updated_at,
        "cartItem"."isLabelled",
        "cartItem"."isPortioned",
        "cartItem".accuracy,
        "cartItem"."ingredientSachetId",
        "cartItem"."isAddOn",
        "cartItem"."addOnLabel",
        "cartItem"."addOnPrice",
        "cartItem"."isAutoAdded",
        "cartItem"."inventoryProductBundleId",
        "cartItem"."subscriptionOccurenceProductId",
        "cartItem"."subscriptionOccurenceAddOnProductId",
        "cartItem"."packingStatus",
        "cartItem".id AS "rootCartItemId",
        ("cartItem".id) :: character varying(1000) AS path,
        1 AS level,
        (
            SELECT
                count("cartItem_1".id) AS count
            FROM
                "order"."cartItem" "cartItem_1"
            WHERE
                ("cartItem".id = "cartItem_1"."parentCartItemId")
        ) AS count,
        CASE
            WHEN ("cartItem"."productOptionId" IS NOT NULL) THEN (
                SELECT
                    "productOption".type
                FROM
                    products."productOption"
                WHERE
                    (
                        "productOption".id = "cartItem"."productOptionId"
                    )
            )
            ELSE NULL :: text
        END AS "productOptionType",
        "cartItem".status,
        "cartItem"."modifierOptionId"
    FROM
        "order"."cartItem"
    WHERE
        ("cartItem"."productId" IS NOT NULL)
    UNION
    SELECT
        c.id,
        COALESCE(c."cartId", p."cartId") AS "cartId",
        c."parentCartItemId",
        c."isModifier",
        p."productId",
        COALESCE(c."productOptionId", p."productOptionId") AS "productOptionId",
        COALESCE(
            c."comboProductComponentId",
            p."comboProductComponentId"
        ) AS "comboProductComponentId",
        COALESCE(
            c."customizableProductComponentId",
            p."customizableProductComponentId"
        ) AS "customizableProductComponentId",
        COALESCE(c."simpleRecipeYieldId", p."simpleRecipeYieldId") AS "simpleRecipeYieldId",
        COALESCE(c."sachetItemId", p."sachetItemId") AS "sachetItemId",
        COALESCE(c."subRecipeYieldId", p."subRecipeYieldId") AS "subRecipeYieldId",
        c."isAssembled",
        c."unitPrice",
        c."refundPrice",
        c."stationId",
        c."labelTemplateId",
        c."packagingId",
        c."instructionCardTemplateId",
        c."assemblyStatus",
        c."position",
        c.created_at,
        c.updated_at,
        c."isLabelled",
        c."isPortioned",
        c.accuracy,
        c."ingredientSachetId",
        c."isAddOn",
        c."addOnLabel",
        c."addOnPrice",
        c."isAutoAdded",
        c."inventoryProductBundleId",
        c."subscriptionOccurenceProductId",
        c."subscriptionOccurenceAddOnProductId",
        c."packingStatus",
        p."rootCartItemId",
        ((((p.path) :: text || '->' :: text) || c.id)) :: character varying(1000) AS path,
        (p.level + 1) AS level,
        (
            SELECT
                count("cartItem".id) AS count
            FROM
                "order"."cartItem"
            WHERE
                ("cartItem"."parentCartItemId" = c.id)
        ) AS count,
        CASE
            WHEN (c."productOptionId" IS NOT NULL) THEN (
                SELECT
                    "productOption".type
                FROM
                    products."productOption"
                WHERE
                    ("productOption".id = c."productOptionId")
            )
            WHEN (p."productOptionId" IS NOT NULL) THEN (
                SELECT
                    "productOption".type
                FROM
                    products."productOption"
                WHERE
                    ("productOption".id = p."productOptionId")
            )
            ELSE NULL :: text
        END AS "productOptionType",
        c.status,
        COALESCE(c."modifierOptionId", p."modifierOptionId") AS "modifierOptionId"
    FROM
        (
            "order"."cartItem" c
            JOIN parent p ON ((p.id = c."parentCartItemId"))
        )
)
SELECT
    parent.id,
    parent."cartId",
    parent."parentCartItemId",
    parent."isModifier",
    parent."productId",
    parent."productOptionId",
    parent."comboProductComponentId",
    parent."customizableProductComponentId",
    parent."simpleRecipeYieldId",
    parent."sachetItemId",
    parent."isAssembled",
    parent."unitPrice",
    parent."refundPrice",
    parent."stationId",
    parent."labelTemplateId",
    parent."packagingId",
    parent."instructionCardTemplateId",
    parent."assemblyStatus",
    parent."position",
    parent.created_at,
    parent.updated_at,
    parent."isLabelled",
    parent."isPortioned",
    parent.accuracy,
    parent."ingredientSachetId",
    parent."isAddOn",
    parent."addOnLabel",
    parent."addOnPrice",
    parent."isAutoAdded",
    parent."inventoryProductBundleId",
    parent."subscriptionOccurenceProductId",
    parent."subscriptionOccurenceAddOnProductId",
    parent."packingStatus",
    parent."rootCartItemId",
    parent.path,
    parent.level,
    parent.count,
    CASE
        WHEN (parent.level = 1) THEN 'productItem' :: text
        WHEN (
            (parent.level = 2)
            AND (parent.count > 0)
        ) THEN 'productItemComponent' :: text
        WHEN (
            (parent.level = 2)
            AND (parent.count = 0)
        ) THEN 'orderItem' :: text
        WHEN (parent.level = 3) THEN 'orderItem' :: text
        WHEN (parent.level = 4) THEN 'orderItemSachet' :: text
        WHEN (parent.level > 4) THEN 'orderItemSachetComponent' :: text
        ELSE NULL :: text
    END AS "levelType",
    btrim(
        COALESCE(
            concat(
                (
                    SELECT
                        product.name
                    FROM
                        products.product
                    WHERE
                        (product.id = parent."productId")
                ),
                (
                    SELECT
                        (
                            ' -> ' :: text || "productOptionView"."displayName"
                        )
                    FROM
                        products."productOptionView"
                    WHERE
                        (
                            "productOptionView".id = parent."productOptionId"
                        )
                ),
                (
                    SELECT
                        (' -> ' :: text || "comboProductComponent".label)
                    FROM
                        products."comboProductComponent"
                    WHERE
                        (
                            "comboProductComponent".id = parent."comboProductComponentId"
                        )
                ),
                (
                    SELECT
                        (
                            ' -> ' :: text || "simpleRecipeYieldView"."displayName"
                        )
                    FROM
                        "simpleRecipe"."simpleRecipeYieldView"
                    WHERE
                        (
                            "simpleRecipeYieldView".id = parent."simpleRecipeYieldId"
                        )
                ),
                (
                    SELECT
                        (
                            (' -> ' :: text || '(MOD) -' :: text) || "modifierCategoryOptionView"."displayName"
                        )
                    FROM
                        "onDemand"."modifierCategoryOptionView"
                    WHERE
                        (
                            "modifierCategoryOptionView".id = parent."modifierOptionId"
                        )
                ),
                CASE
                    WHEN (parent."inventoryProductBundleId" IS NOT NULL) THEN (
                        SELECT
                            (
                                ' -> ' :: text || "productOptionView"."displayName"
                            )
                        FROM
                            products."productOptionView"
                        WHERE
                            (
                                "productOptionView".id = (
                                    SELECT
                                        "cartItem"."productOptionId"
                                    FROM
                                        "order"."cartItem"
                                    WHERE
                                        ("cartItem".id = parent."parentCartItemId")
                                )
                            )
                    )
                    ELSE '' :: text
                END,
                (
                    SELECT
                        (
                            ' -> ' :: text || "ingredientSachetView"."displayName"
                        )
                    FROM
                        ingredient."ingredientSachetView"
                    WHERE
                        (
                            "ingredientSachetView".id = parent."ingredientSachetId"
                        )
                ),
                (
                    SELECT
                        (
                            ' -> ' :: text || "sachetItemView"."supplierItemName"
                        )
                    FROM
                        inventory."sachetItemView"
                    WHERE
                        ("sachetItemView".id = parent."sachetItemId")
                )
            ),
            'N/A' :: text
        )
    ) AS "displayName",
    COALESCE(
        (
            SELECT
                "ingredientProcessing"."processingName"
            FROM
                ingredient."ingredientProcessing"
            WHERE
                (
                    "ingredientProcessing".id = (
                        SELECT
                            "ingredientSachet"."ingredientProcessingId"
                        FROM
                            ingredient."ingredientSachet"
                        WHERE
                            (
                                "ingredientSachet".id = parent."ingredientSachetId"
                            )
                    )
                )
        ),
        (
            SELECT
                "sachetItemView"."processingName"
            FROM
                inventory."sachetItemView"
            WHERE
                ("sachetItemView".id = parent."sachetItemId")
        ),
        'N/A' :: text
    ) AS "processingName",
    COALESCE(
        (
            SELECT
                "modeOfFulfillment"."operationConfigId"
            FROM
                ingredient."modeOfFulfillment"
            WHERE
                (
                    "modeOfFulfillment".id = (
                        SELECT
                            "ingredientSachet"."liveMOF"
                        FROM
                            ingredient."ingredientSachet"
                        WHERE
                            (
                                "ingredientSachet".id = "modeOfFulfillment"."ingredientSachetId"
                            )
                    )
                )
        ),
        (
            SELECT
                "productOption"."operationConfigId"
            FROM
                products."productOption"
            WHERE
                ("productOption".id = parent."productOptionId")
        ),
        NULL :: integer
    ) AS "operationConfigId",
    COALESCE(
        (
            SELECT
                "ingredientSachet".unit
            FROM
                ingredient."ingredientSachet"
            WHERE
                (
                    "ingredientSachet".id = parent."ingredientSachetId"
                )
        ),
        (
            SELECT
                "sachetItemView".unit
            FROM
                inventory."sachetItemView"
            WHERE
                ("sachetItemView".id = parent."sachetItemId")
        ),
        (
            SELECT
                "simpleRecipeYield".unit
            FROM
                "simpleRecipe"."simpleRecipeYield"
            WHERE
                (
                    "simpleRecipeYield".id = parent."subRecipeYieldId"
                )
        ),
        NULL :: text
    ) AS "displayUnit",
    COALESCE(
        (
            SELECT
                "ingredientSachet".quantity
            FROM
                ingredient."ingredientSachet"
            WHERE
                (
                    "ingredientSachet".id = parent."ingredientSachetId"
                )
        ),
        (
            SELECT
                "sachetItemView"."unitSize"
            FROM
                inventory."sachetItemView"
            WHERE
                ("sachetItemView".id = parent."sachetItemId")
        ),
        (
            SELECT
                "simpleRecipeYield".quantity
            FROM
                "simpleRecipe"."simpleRecipeYield"
            WHERE
                (
                    "simpleRecipeYield".id = parent."subRecipeYieldId"
                )
        ),
        NULL :: numeric
    ) AS "displayUnitQuantity",
    CASE
        WHEN (parent."subRecipeYieldId" IS NOT NULL) THEN 'subRecipeYield' :: text
        WHEN (parent."ingredientSachetId" IS NOT NULL) THEN 'ingredientSachet' :: text
        WHEN (parent."sachetItemId" IS NOT NULL) THEN 'sachetItem' :: text
        WHEN (parent."simpleRecipeYieldId" IS NOT NULL) THEN 'simpleRecipeYield' :: text
        WHEN (parent."inventoryProductBundleId" IS NOT NULL) THEN 'inventoryProductBundle' :: text
        WHEN (parent."productOptionId" IS NOT NULL) THEN 'productComponent' :: text
        WHEN (parent."productId" IS NOT NULL) THEN 'product' :: text
        ELSE NULL :: text
    END AS "cartItemType",
    CASE
        WHEN (parent."productId" IS NOT NULL) THEN (
            SELECT
                ((product.assets -> 'images' :: text) -> 0)
            FROM
                products.product
            WHERE
                (product.id = parent."productId")
        )
        WHEN (parent."productOptionId" IS NOT NULL) THEN (
            SELECT
                "productOptionView"."displayImage"
            FROM
                products."productOptionView"
            WHERE
                (
                    "productOptionView".id = parent."productOptionId"
                )
        )
        WHEN (parent."simpleRecipeYieldId" IS NOT NULL) THEN (
            SELECT
                "productOptionView"."displayImage"
            FROM
                products."productOptionView"
            WHERE
                (
                    "productOptionView".id = (
                        SELECT
                            "cartItem"."productOptionId"
                        FROM
                            "order"."cartItem"
                        WHERE
                            ("cartItem".id = parent."parentCartItemId")
                    )
                )
        )
        ELSE NULL :: jsonb
    END AS "displayImage",
    CASE
        WHEN (parent."sachetItemId" IS NOT NULL) THEN (
            SELECT
                "sachetItemView"."bulkDensity"
            FROM
                inventory."sachetItemView"
            WHERE
                ("sachetItemView".id = parent."sachetItemId")
        )
        ELSE NULL :: numeric
    END AS "displayBulkDensity",
    parent."productOptionType",
    COALESCE(
        (
            SELECT
                "simpleRecipeComponent_productOptionType"."orderMode"
            FROM
                "simpleRecipe"."simpleRecipeComponent_productOptionType"
            WHERE
                (
                    (
                        "simpleRecipeComponent_productOptionType"."productOptionType" = parent."productOptionType"
                    )
                    AND (
                        "simpleRecipeComponent_productOptionType"."simpleRecipeComponentId" = (
                            SELECT
                                "simpleRecipeYield_ingredientSachet"."simpleRecipeIngredientProcessingId"
                            FROM
                                "simpleRecipe"."simpleRecipeYield_ingredientSachet"
                            WHERE
                                (
                                    (
                                        "simpleRecipeYield_ingredientSachet"."recipeYieldId" = parent."simpleRecipeYieldId"
                                    )
                                    AND (
                                        (
                                            "simpleRecipeYield_ingredientSachet"."ingredientSachetId" = parent."ingredientSachetId"
                                        )
                                        OR (
                                            "simpleRecipeYield_ingredientSachet"."subRecipeYieldId" = parent."subRecipeYieldId"
                                        )
                                    )
                                )
                            LIMIT
                                1
                        )
                    )
                )
            LIMIT
                1
        ), (
            SELECT
                "simpleRecipe_productOptionType"."orderMode"
            FROM
                "simpleRecipe"."simpleRecipe_productOptionType"
            WHERE
                (
                    "simpleRecipe_productOptionType"."simpleRecipeId" = (
                        SELECT
                            "simpleRecipeYield"."simpleRecipeId"
                        FROM
                            "simpleRecipe"."simpleRecipeYield"
                        WHERE
                            (
                                "simpleRecipeYield".id = parent."simpleRecipeYieldId"
                            )
                    )
                )
        ),
        (
            SELECT
                "productOptionType"."orderMode"
            FROM
                products."productOptionType"
            WHERE
                (
                    "productOptionType".title = parent."productOptionType"
                )
        ),
        'undefined' :: text
    ) AS "orderMode",
    parent."subRecipeYieldId",
    COALESCE(
        (
            SELECT
                "simpleRecipeYield".serving
            FROM
                "simpleRecipe"."simpleRecipeYield"
            WHERE
                (
                    "simpleRecipeYield".id = parent."subRecipeYieldId"
                )
        ),
        (
            SELECT
                "simpleRecipeYield".serving
            FROM
                "simpleRecipe"."simpleRecipeYield"
            WHERE
                (
                    "simpleRecipeYield".id = parent."simpleRecipeYieldId"
                )
        ),
        NULL :: numeric
    ) AS "displayServing",
    CASE
        WHEN (parent."ingredientSachetId" IS NOT NULL) THEN (
            SELECT
                "ingredientSachet"."ingredientId"
            FROM
                ingredient."ingredientSachet"
            WHERE
                (
                    "ingredientSachet".id = parent."ingredientSachetId"
                )
        )
        ELSE NULL :: integer
    END AS "ingredientId",
    CASE
        WHEN (parent."ingredientSachetId" IS NOT NULL) THEN (
            SELECT
                "ingredientSachet"."ingredientProcessingId"
            FROM
                ingredient."ingredientSachet"
            WHERE
                (
                    "ingredientSachet".id = parent."ingredientSachetId"
                )
        )
        ELSE NULL :: integer
    END AS "ingredientProcessingId",
    CASE
        WHEN (parent."sachetItemId" IS NOT NULL) THEN (
            SELECT
                "sachetItem"."bulkItemId"
            FROM
                inventory."sachetItem"
            WHERE
                ("sachetItem".id = parent."sachetItemId")
        )
        ELSE NULL :: integer
    END AS "bulkItemId",
    CASE
        WHEN (parent."sachetItemId" IS NOT NULL) THEN (
            SELECT
                "bulkItem"."supplierItemId"
            FROM
                inventory."bulkItem"
            WHERE
                (
                    "bulkItem".id = (
                        SELECT
                            "sachetItem"."bulkItemId"
                        FROM
                            inventory."sachetItem"
                        WHERE
                            ("sachetItem".id = parent."sachetItemId")
                    )
                )
        )
        ELSE NULL :: integer
    END AS "supplierItemId",
    parent.status,
    parent."modifierOptionId"
FROM
    parent;

CREATE VIEW "order"."ordersAggregate" AS
SELECT
    "orderStatusEnum".title,
    "orderStatusEnum".value,
    "orderStatusEnum".index,
    (
        SELECT
            COALESCE(sum("order"."amountPaid"), (0) :: numeric) AS "coalesce"
        FROM
            (
                "order"."order"
                JOIN "order".cart ON (("order"."cartId" = cart.id))
            )
        WHERE
            (
                (
                    ("order"."isRejected" IS NULL)
                    OR ("order"."isRejected" = false)
                )
                AND (cart.status = "orderStatusEnum".value)
            )
    ) AS "totalOrderSum",
    (
        SELECT
            COALESCE(avg("order"."amountPaid"), (0) :: numeric) AS "coalesce"
        FROM
            (
                "order"."order"
                JOIN "order".cart ON (("order"."cartId" = cart.id))
            )
        WHERE
            (
                (
                    ("order"."isRejected" IS NULL)
                    OR ("order"."isRejected" = false)
                )
                AND (cart.status = "orderStatusEnum".value)
            )
    ) AS "totalOrderAverage",
    (
        SELECT
            count(*) AS count
        FROM
            (
                "order"."order"
                JOIN "order".cart ON (("order"."cartId" = cart.id))
            )
        WHERE
            (
                (
                    ("order"."isRejected" IS NULL)
                    OR ("order"."isRejected" = false)
                )
                AND (cart.status = "orderStatusEnum".value)
            )
    ) AS "totalOrders"
FROM
    "order"."orderStatusEnum"
ORDER BY
    "orderStatusEnum".index;

CREATE VIEW subscription."subscriptionOccurenceView" AS
SELECT
    (
        now() < "subscriptionOccurence"."cutoffTimeStamp"
    ) AS "isValid",
    "subscriptionOccurence".id,
    (now() > "subscriptionOccurence"."startTimeStamp") AS "isVisible",
    (
        SELECT
            count(*) AS count
        FROM
            crm.brand_customer
        WHERE
            (
                brand_customer."subscriptionId" = "subscriptionOccurence"."subscriptionId"
            )
    ) AS "totalSubscribers",
    (
        SELECT
            count(*) AS "skippedCustomers"
        FROM
            subscription."subscriptionOccurence_customer"
        WHERE
            (
                (
                    "subscriptionOccurence_customer"."subscriptionOccurenceId" = "subscriptionOccurence".id
                )
                AND (
                    "subscriptionOccurence_customer"."isSkipped" = true
                )
            )
    ) AS "skippedCustomers",
    (
        SELECT
            count(
                DISTINCT ROW(
                    "subscriptionOccurence_product"."productOptionId",
                    "subscriptionOccurence_product"."productCategory"
                )
            ) AS count
        FROM
            subscription."subscriptionOccurence_product"
        WHERE
            (
                "subscriptionOccurence_product"."subscriptionOccurenceId" = "subscriptionOccurence".id
            )
    ) AS "weeklyProductChoices",
    (
        SELECT
            count(
                DISTINCT ROW(
                    "subscriptionOccurence_product"."productOptionId",
                    "subscriptionOccurence_product"."productCategory"
                )
            ) AS count
        FROM
            subscription."subscriptionOccurence_product"
        WHERE
            (
                "subscriptionOccurence_product"."subscriptionId" = "subscriptionOccurence"."subscriptionId"
            )
    ) AS "allTimeProductChoices",
    (
        SELECT
            (
                (
                    SELECT
                        count(
                            DISTINCT ROW(
                                "subscriptionOccurence_product"."productOptionId",
                                "subscriptionOccurence_product"."productCategory"
                            )
                        ) AS count
                    FROM
                        subscription."subscriptionOccurence_product"
                    WHERE
                        (
                            "subscriptionOccurence_product"."subscriptionOccurenceId" = "subscriptionOccurence".id
                        )
                ) + (
                    SELECT
                        count(
                            DISTINCT ROW(
                                "subscriptionOccurence_product"."productOptionId",
                                "subscriptionOccurence_product"."productCategory"
                            )
                        ) AS count
                    FROM
                        subscription."subscriptionOccurence_product"
                    WHERE
                        (
                            "subscriptionOccurence_product"."subscriptionId" = "subscriptionOccurence"."subscriptionId"
                        )
                )
            )
    ) AS "totalProductChoices",
    (
        SELECT
            subscription."assignWeekNumberToSubscriptionOccurence"("subscriptionOccurence".id) AS "subscriptionWeekRank"
    ) AS "subscriptionWeekRank",
    "subscriptionOccurence"."fulfillmentDate",
    "subscriptionOccurence"."subscriptionId"
FROM
    subscription."subscriptionOccurence";

CREATE VIEW subscription."view_brand_customer_subscriptionOccurence" AS WITH view AS (
    SELECT
        s.id AS "subscriptionOccurenceId",
        c.id AS "brand_customerId",
        s.id,
        s."fulfillmentDate",
        s."cutoffTimeStamp",
        s."subscriptionId",
        s."startTimeStamp",
        s.assets,
        s."subscriptionAutoSelectOption",
        s."subscriptionItemCountId",
        s."subscriptionServingId",
        s."subscriptionTitleId",
        (
            SELECT
                count(*) AS count
            FROM
                subscription."subscriptionOccurence_customer"
            WHERE
                (
                    (
                        "subscriptionOccurence_customer"."brand_customerId" = c.id
                    )
                    AND (
                        "subscriptionOccurence_customer"."subscriptionId" = c."subscriptionId"
                    )
                    AND (
                        "subscriptionOccurence_customer"."subscriptionOccurenceId" <= s.id
                    )
                )
        ) AS "allTimeRank",
        (
            SELECT
                count(*) AS count
            FROM
                subscription."subscriptionOccurence_customer"
            WHERE
                (
                    (
                        "subscriptionOccurence_customer"."isSkipped" = true
                    )
                    AND (
                        "subscriptionOccurence_customer"."brand_customerId" = c.id
                    )
                    AND (
                        "subscriptionOccurence_customer"."subscriptionId" = c."subscriptionId"
                    )
                    AND (
                        "subscriptionOccurence_customer"."subscriptionOccurenceId" <= s.id
                    )
                )
        ) AS "skippedBeforeThis"
    FROM
        (
            subscription."subscriptionOccurence" s
            JOIN crm.brand_customer c ON ((c."subscriptionId" = s."subscriptionId"))
        )
    WHERE
        (s."startTimeStamp" > now())
)
SELECT
    view."subscriptionOccurenceId",
    view."brand_customerId",
    view.id,
    view."fulfillmentDate",
    view."cutoffTimeStamp",
    view."subscriptionId",
    view."startTimeStamp",
    view.assets,
    view."subscriptionAutoSelectOption",
    view."subscriptionItemCountId",
    view."subscriptionServingId",
    view."subscriptionTitleId",
    view."allTimeRank",
    view."skippedBeforeThis"
FROM
    view;

CREATE VIEW subscription.view_subscription AS
SELECT
    subscription.id,
    subscription."subscriptionItemCountId",
    subscription.rrule,
    subscription."metaDetails",
    subscription."cutOffTime",
    subscription."leadTime",
    subscription."startTime",
    subscription."startDate",
    subscription."endDate",
    subscription."defaultSubscriptionAutoSelectOption",
    subscription."reminderSettings",
    subscription."subscriptionServingId",
    subscription."subscriptionTitleId",
    (
        SELECT
            count(*) AS count
        FROM
            crm.brand_customer
        WHERE
            (
                brand_customer."subscriptionId" = subscription.id
            )
    ) AS "totalSubscribers",
    (
        SELECT
            "subscriptionTitle".title
        FROM
            subscription."subscriptionTitle"
        WHERE
            (
                "subscriptionTitle".id = subscription."subscriptionTitleId"
            )
    ) AS title,
    (
        SELECT
            "subscriptionServing"."servingSize"
        FROM
            subscription."subscriptionServing"
        WHERE
            (
                "subscriptionServing".id = subscription."subscriptionServingId"
            )
    ) AS "subscriptionServingSize",
    (
        SELECT
            "subscriptionItemCount".count
        FROM
            subscription."subscriptionItemCount"
        WHERE
            (
                "subscriptionItemCount".id = subscription."subscriptionItemCountId"
            )
    ) AS "subscriptionItemCount"
FROM
    subscription.subscription;

CREATE VIEW subscription."view_subscriptionItemCount" AS
SELECT
    "subscriptionItemCount".id,
    "subscriptionItemCount"."subscriptionServingId",
    "subscriptionItemCount".count,
    "subscriptionItemCount"."metaDetails",
    "subscriptionItemCount".price,
    "subscriptionItemCount"."isActive",
    "subscriptionItemCount".tax,
    "subscriptionItemCount"."isTaxIncluded",
    "subscriptionItemCount"."subscriptionTitleId",
    (
        SELECT
            count(*) AS count
        FROM
            crm.brand_customer
        WHERE
            (
                brand_customer."subscriptionItemCountId" = "subscriptionItemCount".id
            )
    ) AS "totalSubscribers"
FROM
    subscription."subscriptionItemCount";

CREATE VIEW subscription."view_subscriptionOccurenceMenuHealth" AS
SELECT
    (
        SELECT
            "subscriptionItemCount".count
        FROM
            subscription."subscriptionItemCount"
        WHERE
            (
                "subscriptionItemCount".id = "subscriptionOccurence"."subscriptionItemCountId"
            )
    ) AS "totalProductsToBeAdded",
    (
        SELECT
            "subscriptionOccurenceView"."weeklyProductChoices"
        FROM
            subscription."subscriptionOccurenceView"
        WHERE
            (
                "subscriptionOccurenceView".id = "subscriptionOccurence".id
            )
    ) AS "weeklyProductChoices",
    (
        SELECT
            "subscriptionOccurenceView"."allTimeProductChoices"
        FROM
            subscription."subscriptionOccurenceView"
        WHERE
            (
                "subscriptionOccurenceView".id = "subscriptionOccurence".id
            )
    ) AS "allTimeProductChoices",
    (
        SELECT
            "subscriptionOccurenceView"."totalProductChoices"
        FROM
            subscription."subscriptionOccurenceView"
        WHERE
            (
                "subscriptionOccurenceView".id = "subscriptionOccurence".id
            )
    ) AS "totalProductChoices",
    (
        SELECT
            (
                (
                    SELECT
                        "subscriptionOccurenceView"."totalProductChoices"
                    FROM
                        subscription."subscriptionOccurenceView"
                    WHERE
                        (
                            "subscriptionOccurenceView".id = "subscriptionOccurence".id
                        )
                ) / (
                    SELECT
                        "subscriptionItemCount".count
                    FROM
                        subscription."subscriptionItemCount"
                    WHERE
                        (
                            "subscriptionItemCount".id = "subscriptionOccurence"."subscriptionItemCountId"
                        )
                )
            )
    ) AS "choicePerSelection"
FROM
    subscription."subscriptionOccurence";

CREATE VIEW subscription."view_subscriptionOccurence_customer" AS WITH view AS (
    SELECT
        s."subscriptionOccurenceId",
        s."keycloakId",
        s."cartId",
        s."isSkipped",
        s."isAuto",
        s."brand_customerId",
        s."subscriptionId",
        (
            SELECT
                count(*) AS count
            FROM
                subscription."subscriptionOccurence_customer" a
            WHERE
                (
                    (
                        a."subscriptionOccurenceId" <= s."subscriptionOccurenceId"
                    )
                    AND (a."brand_customerId" = s."brand_customerId")
                )
        ) AS "allTimeRank",
        (
            SELECT
                COALESCE(count(*), (0) :: bigint) AS "coalesce"
            FROM
                "order"."cartItem"
            WHERE
                (
                    ("cartItem"."cartId" = s."cartId")
                    AND ("cartItem"."isAddOn" = false)
                    AND ("cartItem"."parentCartItemId" IS NULL)
                )
        ) AS "addedProductsCount",
        (
            SELECT
                "subscriptionItemCount".count
            FROM
                subscription."subscriptionItemCount"
            WHERE
                (
                    "subscriptionItemCount".id = (
                        SELECT
                            "subscriptionOccurence"."subscriptionItemCountId"
                        FROM
                            subscription."subscriptionOccurence"
                        WHERE
                            (
                                "subscriptionOccurence".id = s."subscriptionOccurenceId"
                            )
                    )
                )
        ) AS "totalProductsToBeAdded",
        (
            SELECT
                count(*) AS count
            FROM
                subscription."subscriptionOccurence_customer" a
            WHERE
                (
                    (
                        a."subscriptionOccurenceId" <= s."subscriptionOccurenceId"
                    )
                    AND (a."isSkipped" = true)
                    AND (a."brand_customerId" = s."brand_customerId")
                )
        ) AS "skippedAtThisStage"
    FROM
        subscription."subscriptionOccurence_customer" s
)
SELECT
    view."subscriptionOccurenceId",
    view."keycloakId",
    view."cartId",
    view."isSkipped",
    view."isAuto",
    view."brand_customerId",
    view."subscriptionId",
    view."allTimeRank",
    view."addedProductsCount",
    view."totalProductsToBeAdded",
    view."skippedAtThisStage",
    (
        (
            (view."skippedAtThisStage") :: numeric / (view."allTimeRank") :: numeric
        ) * (100) :: numeric
    ) AS "percentageSkipped"
FROM
    view;

CREATE VIEW subscription."view_subscriptionServing" AS
SELECT
    "subscriptionServing".id,
    "subscriptionServing"."subscriptionTitleId",
    "subscriptionServing"."servingSize",
    "subscriptionServing"."metaDetails",
    "subscriptionServing"."defaultSubscriptionItemCountId",
    "subscriptionServing"."isActive",
    (
        SELECT
            count(*) AS count
        FROM
            crm.brand_customer
        WHERE
            (
                brand_customer."subscriptionServingId" = "subscriptionServing".id
            )
    ) AS "totalSubscribers"
FROM
    subscription."subscriptionServing";

CREATE VIEW subscription."view_subscriptionTitle" AS
SELECT
    "subscriptionTitle".id,
    "subscriptionTitle".title,
    "subscriptionTitle"."metaDetails",
    "subscriptionTitle"."defaultSubscriptionServingId",
    "subscriptionTitle".created_at,
    "subscriptionTitle".updated_at,
    "subscriptionTitle"."isActive",
    (
        SELECT
            count(*) AS count
        FROM
            crm.brand_customer
        WHERE
            (
                brand_customer."subscriptionTitleId" = "subscriptionTitle".id
            )
    ) AS "totalSubscribers"
FROM
    subscription."subscriptionTitle";