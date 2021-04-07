CREATE SCHEMA brands;

CREATE SCHEMA content;

CREATE SCHEMA crm;

CREATE SCHEMA datahub_schema;

CREATE SCHEMA "deviceHub";

CREATE SCHEMA editor;

CREATE SCHEMA fulfilment;

CREATE SCHEMA imports;

CREATE SCHEMA ingredient;

CREATE SCHEMA insights;

CREATE SCHEMA instructions;

CREATE SCHEMA inventory;

CREATE SCHEMA master;

CREATE SCHEMA notifications;

CREATE SCHEMA "onDemand";

CREATE SCHEMA "order";

CREATE SCHEMA packaging;

CREATE SCHEMA products;

CREATE SCHEMA rules;

CREATE SCHEMA safety;

CREATE SCHEMA settings;

CREATE SCHEMA "simpleRecipe";

CREATE SCHEMA subscription;

CREATE SCHEMA website;

CREATE TYPE public.summary AS (
  pending jsonb,
  underprocessing jsonb,
  readytodispatch jsonb,
  outfordelivery jsonb,
  delivered jsonb,
  rejectedcancelled jsonb
);

CREATE FUNCTION brands."getSettings"(brandid integer) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE settings jsonb = '{}';

setting record;

brandValue jsonb;

res jsonb;

BEGIN FOR setting IN
SELECT
  *
FROM
  brands."storeSetting" LOOP
SELECT
  value
FROM
  brands."brand_storeSetting"
WHERE
  "storeSettingId" = setting.id
  AND "brandId" = brandId INTO brandValue;

settings := settings || jsonb_build_object(
  setting.identifier,
  COALESCE(brandValue, setting.value)
);

END LOOP;

res := jsonb_build_object(
  'brand',
  jsonb_build_object(
    'logo',
    settings -> 'Brand Logo' ->> 'url',
    'name',
    settings -> 'Brand Name' ->> 'name',
    'navLinks',
    settings -> 'Nav Links',
    'contact',
    settings -> 'Contact',
    'policyAvailability',
    settings -> 'Policy Availability'
  ),
  'visual',
  jsonb_build_object(
    'color',
    settings -> 'Primary Color' ->> 'color',
    'slides',
    settings -> 'Slides',
    'appTitle',
    settings -> 'App Title' ->> 'title',
    'favicon',
    settings -> 'Favicon' ->> 'url'
  ),
  'availability',
  jsonb_build_object(
    'store',
    settings -> 'Store Availability',
    'pickup',
    settings -> 'Pickup Availability',
    'delivery',
    settings -> 'Delivery Availability',
    'referral',
    settings -> 'Referral Availability',
    'location',
    settings -> 'Location',
    'payments',
    settings -> 'Store Live'
  ),
  'rewardsSettings',
  jsonb_build_object(
    'isLoyaltyPointsAvailable',
    (
      settings -> 'Loyalty Points Availability' ->> 'isAvailable'
    ) :: boolean,
    'isWalletAvailable',
    (
      settings -> 'Wallet Availability' ->> 'isAvailable'
    ) :: boolean,
    'isCouponsAvailable',
    (
      settings -> 'Coupons Availability' ->> 'isAvailable'
    ) :: boolean,
    'loyaltyPointsUsage',
    settings -> 'Loyalty Points Usage'
  ),
  'appSettings',
  jsonb_build_object(
    'scripts',
    settings -> 'Scripts' ->> 'value'
  )
);

RETURN res;

END;

$ $;

CREATE FUNCTION content.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE FUNCTION crm."createBrandCustomer"(keycloakid text, brandid integer) RETURNS void LANGUAGE plpgsql AS $ $ BEGIN
INSERT INTO
  crm."brand_customer"("keycloakId", "brandId")
VALUES
  (keycloakId, brandId);

END;

$ $;

CREATE FUNCTION crm."createCustomer2"(
  keycloakid text,
  brandid integer,
  email text,
  clientid text
) RETURNS integer LANGUAGE plpgsql AS $ $ DECLARE customerId int;

BEGIN
INSERT INTO
  crm.customer("keycloakId", "email", "sourceBrandId")
VALUES
  (keycloakId, email, brandId) RETURNING id INTO customerId;

RETURN customerId;

END;

$ $;

CREATE FUNCTION crm."createCustomerWLR"() RETURNS trigger LANGUAGE plpgsql AS $ $ BEGIN
INSERT INTO
  crm.wallet("keycloakId", "brandId")
VALUES
  (NEW."keycloakId", NEW."brandId");

INSERT INTO
  crm."loyaltyPoint"("keycloakId", "brandId")
VALUES
  (NEW."keycloakId", NEW."brandId");

INSERT INTO
  crm."customerReferral"("keycloakId", "brandId")
VALUES
  (NEW."keycloakId", NEW."brandId");

RETURN NULL;

END;

$ $;

CREATE FUNCTION crm."deductLoyaltyPointsPostOrder"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE cart record;

amount numeric;

loyaltyPointId int;

setting record;

temp record;

rate numeric;

BEGIN IF NEW."keycloakId" IS NULL THEN RETURN NULL;

END IF;

SELECT
  *
FROM
  "order"."cart"
WHERE
  id = NEW."cartId" INTO cart;

SELECT
  id
FROM
  crm."loyaltyPoint"
WHERE
  "keycloakId" = NEW."keycloakId"
  AND "brandId" = NEW."brandId" INTO loyaltyPointId;

IF cart."loyaltyPointsUsed" > 0 THEN
SELECT
  crm."getLoyaltyPointsConversionRate"(NEW."brandId") INTO rate;

amount := ROUND((cart."loyaltyPointsUsed" * rate), 2);

INSERT INTO
  crm."loyaltyPointTransaction"(
    "loyaltyPointId",
    "points",
    "orderCartId",
    "type",
    "amountRedeemed"
  )
VALUES
  (
    loyaltyPointId,
    cart."loyaltyPointsUsed",
    cart.id,
    'DEBIT',
    amount
  );

END IF;

RETURN NULL;

END $ $;

CREATE FUNCTION crm."deductWalletAmountPostOrder"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE cart record;

walletId int;

BEGIN IF NEW."keycloakId" IS NULL THEN RETURN NULL;

END IF;

SELECT
  *
FROM
  "order"."cart"
WHERE
  id = NEW."cartId" INTO cart;

SELECT
  id
FROM
  crm."wallet"
WHERE
  "keycloakId" = NEW."keycloakId"
  AND "brandId" = NEW."brandId" INTO walletId;

IF cart."walletAmountUsed" > 0 THEN
INSERT INTO
  crm."walletTransaction"("walletId", "amount", "orderCartId", "type")
VALUES
  (
    walletId,
    cart."walletAmountUsed",
    cart.id,
    'DEBIT'
  );

END IF;

RETURN NULL;

END $ $;

CREATE TABLE crm."customerData" (id integer NOT NULL, data jsonb NOT NULL);

CREATE FUNCTION crm."getCustomer2"(
  keycloakid text,
  brandid integer,
  customeremail text,
  clientid text
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE customer record;

brandCustomer record;

newCustomerId int;

BEGIN
SELECT
  *
from
  crm.customer
WHERE
  "keycloakId" = keycloakId INTO customer;

IF customer IS NULL THEN
SELECT
  crm."createCustomer2"(keycloakId, brandId, customerEmail, clientId) INTO newCustomerId;

END IF;

SELECT
  *
FROM
  crm."brand_customer"
WHERE
  "keycloakId" = keycloakId
  AND "brandId" = brandId INTO brandCustomer;

IF brandCustomer is NULL THEN PERFORM crm."createBrandCustomer"(keycloakId, brandId);

END IF;

-- SELECT * FROM crm.customer WHERE "keycloakId" = keycloakId INTO customer;
RETURN QUERY
SELECT
  1 AS id,
  jsonb_build_object('email', customeremail) AS data;

-- RETURN jsonb_build_object('id', COALESCE(customer.id, newCustomerId), 'email', customeremail, 'isTest', false, 'keycloakId', keycloakid);
END;

$ $;

CREATE FUNCTION crm."getLoyaltyPointsConversionRate"(brandid integer) RETURNS numeric LANGUAGE plpgsql AS $ $ DECLARE setting record;

temp record;

obj jsonb;

BEGIN
SELECT
  *
FROM
  brands."storeSetting"
WHERE
  "type" = 'rewards'
  and "identifier" = 'Loyalty Points Usage' INTO setting;

SELECT
  *
FROM
  brands."brand_storeSetting"
WHERE
  "brandId" = brandid
  AND "storeSettingId" = setting.id INTO temp;

-- IF temp IS NOT NULL THEN
--     setting := temp;
-- END IF;
SELECT
  setting.value INTO obj;

RETURN 0.01;

END $ $;

CREATE FUNCTION public.defaultid(schema text, tab text, col text) RETURNS integer LANGUAGE plpgsql AS $ $ declare idVal integer;

queryname text;

existsquery text;

sequencename text;

BEGIN sequencename = (
  '"' || schema || '"' || '.' || '"' || tab || '_' || col || '_seq' || '"'
) :: text;

execute (
  'CREATE SEQUENCE IF NOT EXISTS' || sequencename || 'minvalue 1000 OWNED BY "' || schema || '"."' || tab || '"."' || col || '"'
);

select
  ('select nextval(''' || sequencename || ''')') into queryname;

select
  call(queryname) :: integer into idVal;

select
  (
    'select exists(select "' || col || '" from "' || schema || '"."' || tab || '" where "' || col || '" = ' || idVal || ')'
  ) into existsquery;

WHILE exec(existsquery) = true LOOP
select
  call(queryname) into idVal;

select
  (
    'select exists(select "' || col || '" from "' || schema || '"."' || tab || '" where "' || col || '" = ' || idVal || ')'
  ) into existsquery;

END LOOP;

return idVal;

END;

$ $;

CREATE TABLE crm.campaign (
  id integer DEFAULT public.defaultid('crm' :: text, 'campaign' :: text, 'id' :: text) NOT NULL,
  type text NOT NULL,
  "metaDetails" jsonb,
  "conditionId" integer,
  "isRewardMulti" boolean DEFAULT false NOT NULL,
  "isActive" boolean DEFAULT false NOT NULL,
  priority integer DEFAULT 1 NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  "isArchived" boolean DEFAULT false NOT NULL
);

COMMENT ON TABLE crm.campaign IS 'This table contains all the campaigns across the system.';

COMMENT ON COLUMN crm.campaign.id IS 'Auto generated id for the campaign table row.';

COMMENT ON COLUMN crm.campaign.type IS 'A campaign can be of many types, differentiating how they are implemented. This type here refers to that. The value in this should come from the campaignType table.';

COMMENT ON COLUMN crm.campaign."metaDetails" IS 'This jsonb value contains all the meta details like title, description and picture for this campaign.';

COMMENT ON COLUMN crm.campaign."conditionId" IS 'This represents the rule condition that would be checked for trueness before considering this campaign for implementation for rewards.';

COMMENT ON COLUMN crm.campaign."isRewardMulti" IS 'A campaign could have many rewards. If this is true, that means that all the valid rewards would be applied to the transaction. If false, it would pick the valid reward with highest priority.';

COMMENT ON COLUMN crm.campaign."isActive" IS 'Whether this campaign is active or not.';

COMMENT ON COLUMN crm.campaign."isArchived" IS 'Marks the deletion of campaign if user attempts to delete it.';

CREATE FUNCTION crm.iscampaignvalid(campaign crm.campaign) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE res json;

temp int;

BEGIN
SELECT
  COUNT(*)
FROM
  crm."reward"
WHERE
  "campaignId" = campaign."id"
LIMIT
  1 into temp;

IF campaign."conditionId" IS NULL
AND temp < 1 THEN res := json_build_object(
  'status',
  false,
  'error',
  'Campaign Condition Or Reward not provided'
);

ELSEIF campaign."conditionId" IS NULL THEN res := json_build_object(
  'status',
  false,
  'error',
  'Campaign Condition not provided'
);

ELSEIF temp < 1 THEN res := json_build_object('status', false, 'error', 'Reward not provided');

ELSEIF campaign."metaDetails" -> 'description' IS NULL
OR coalesce(
  TRIM(campaign."metaDetails" ->> 'description'),
  ''
) = '' THEN res := json_build_object(
  'status',
  false,
  'error',
  'Description not provided'
);

ELSE res := json_build_object('status', true, 'error', '');

END IF;

RETURN res;

END $ $;

CREATE TABLE crm.coupon (
  id integer DEFAULT public.defaultid('crm' :: text, 'coupon' :: text, 'id' :: text) NOT NULL,
  "isActive" boolean DEFAULT false NOT NULL,
  "metaDetails" jsonb,
  code text NOT NULL,
  "isRewardMulti" boolean DEFAULT false NOT NULL,
  "visibleConditionId" integer,
  "isVoucher" boolean DEFAULT false NOT NULL,
  "isArchived" boolean DEFAULT false NOT NULL
);

COMMENT ON TABLE crm.coupon IS 'This table contains all the coupons across the system.';

COMMENT ON COLUMN crm.coupon.id IS 'Auto generated id for the coupon table row.';

COMMENT ON COLUMN crm.coupon."isActive" IS 'Whether this coupon is active or not.';

COMMENT ON COLUMN crm.coupon."metaDetails" IS 'This jsonb value contains all the meta details like title, description and picture for this coupon.';

COMMENT ON COLUMN crm.coupon."isRewardMulti" IS 'A coupon could have many rewards. If this is true, that means that all the valid rewards would be applied to the transaction. If false, it would pick the valid reward with highest priority.';

COMMENT ON COLUMN crm.coupon."visibleConditionId" IS 'This represents the rule condition that would be checked for trueness before showing the coupon in the store. Please note that this condition doesn''t check if reward is valid or not but strictly just maintains the visibility of the coupon.';

COMMENT ON COLUMN crm.coupon."isArchived" IS 'Marks the deletion of coupon if user attempts to delete it.';

CREATE FUNCTION crm.iscouponvalid(coupon crm.coupon) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE res json;

temp int;

BEGIN
SELECT
  COUNT(*)
FROM
  crm."reward"
WHERE
  "couponId" = coupon."id" into temp;

IF coupon."visibleConditionId" IS NULL
AND temp < 1 THEN res := json_build_object(
  'status',
  false,
  'error',
  'Coupon Condition Or Reward not provided'
);

ELSEIF coupon."visibleConditionId" IS NULL THEN res := json_build_object(
  'status',
  false,
  'error',
  'Coupon Condition not provided'
);

ELSEIF temp < 1 THEN res := json_build_object('status', false, 'error', 'Reward not provided');

ELSEIF coupon."metaDetails" -> 'title' IS NULL
OR coalesce(TRIM(coupon."metaDetails" ->> 'title'), '') = '' THEN res := json_build_object('status', false, 'error', 'Title not provided');

ELSEIF coupon."metaDetails" -> 'description' IS NULL
OR coalesce(TRIM(coupon."metaDetails" ->> 'description'), '') = '' THEN res := json_build_object(
  'status',
  false,
  'error',
  'Description not provided'
);

ELSE res := json_build_object('status', true, 'error', '');

END IF;

RETURN res;

END $ $;

CREATE
OR REPLACE FUNCTION crm."postOrderCampaignRewardsTriggerFunction"() RETURNS trigger LANGUAGE plpgsql AS $ function $ DECLARE params jsonb;

rewardsParams jsonb;

campaign record;

condition record;

campaignValidity boolean := false;

rewardValidity boolean;

reward record;

rewardIds int [] DEFAULT '{}';

BEGIN IF NEW."keycloakId" IS NULL THEN RETURN NULL;

END IF;

params := jsonb_build_object(
  'keycloakId',
  NEW."keycloakId",
  'orderId',
  NEW.id :: int,
  'cartId',
  NEW."cartId",
  'brandId',
  NEW."brandId"
);

FOR campaign IN
SELECT
  *
FROM
  crm."campaign"
WHERE
  id IN (
    SELECT
      "campaignId"
    FROM
      crm."brand_campaign"
    WHERE
      "brandId" = (params -> 'brandId') :: int
      AND "isActive" = true
  )
  AND "isActive" = true
  AND "type" = 'Post Order'
ORDER BY
  priority DESC,
  updated_at DESC LOOP params := params || jsonb_build_object(
    'campaignType',
    campaign."type",
    'table',
    TG_TABLE_NAME,
    'campaignId',
    campaign.id,
    'rewardId',
    null
  );

SELECT
  rules."isConditionValidFunc"(campaign."conditionId", params) INTO campaignValidity;

IF campaignValidity = false THEN CONTINUE;

END IF;

FOR reward IN
SELECT
  *
FROM
  crm.reward
WHERE
  "campaignId" = campaign.id
ORDER BY
  position DESC LOOP params := params || jsonb_build_object('rewardId', reward.id);

SELECT
  rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;

IF rewardValidity = true THEN rewardIds := rewardIds || reward.id;

IF campaign."isRewardMulti" = false THEN EXIT;

END IF;

END IF;

END LOOP;

IF array_length(rewardIds, 1) > 0 THEN rewardsParams := params || jsonb_build_object('campaignType', campaign."type");

PERFORM crm."processRewardsForCustomer"(rewardIds, rewardsParams);

END IF;

END LOOP;

RETURN NULL;

END;

$ function $;

CREATE FUNCTION crm."postOrderCouponRewards"() RETURNS trigger LANGUAGE plpgsql STABLE AS $ $ DECLARE rec record;

reward record;

rewardIds int [];

params jsonb;

BEGIN IF NEW."keycloakId" IS NULL THEN RETURN NULL;

END IF;

params := jsonb_build_object(
  'keycloakId',
  NEW."keycloakId",
  'orderId',
  NEW.id,
  'cartId',
  NEW."cartId",
  'brandId',
  NEW."brandId",
  'campaignType',
  'Post Order'
);

FOR rec IN
SELECT
  *
FROM
  "order"."cart_rewards"
WHERE
  "cartId" = NEW."cartId" LOOP
SELECT
  *
FROM
  crm.reward
WHERE
  id = rec."rewardId" INTO reward;

IF reward."type" = 'Loyalty Point Credit'
OR reward."type" = 'Wallet Amount Credit' THEN rewardIds := rewardIds || reward.id;

END IF;

rewardIds := rewardIds || rec."rewardId";

END LOOP;

IF array_length(rewardIds, 1) > 0 THEN PERFORM crm."processRewardsForCustomer"(rewardIds, params);

END IF;

RETURN NULL;

END;

$ $;

CREATE FUNCTION crm."processLoyaltyPointTransaction"() RETURNS trigger LANGUAGE plpgsql AS $ $ BEGIN IF NEW."type" = 'CREDIT' THEN
UPDATE
  crm."loyaltyPoint"
SET
  points = points + NEW.points
WHERE
  id = NEW."loyaltyPointId";

ELSE
UPDATE
  crm."loyaltyPoint"
SET
  points = points - NEW.points
WHERE
  id = NEW."loyaltyPointId";

END IF;

RETURN NULL;

END;

$ $;

CREATE FUNCTION crm."processRewardsForCustomer"(rewardids integer [], params jsonb) RETURNS void LANGUAGE plpgsql AS $ $ DECLARE reward record;

loyaltyPointId int;

walletId int;

pointsToBeCredited int;

amountToBeCredited numeric;

cartAmount numeric;

returnedId int;

BEGIN FOR reward IN
SELECT
  *
FROM
  crm.reward
WHERE
  id = ANY(rewardIds) LOOP IF reward."type" = 'Loyalty Point Credit' THEN
SELECT
  id
FROM
  crm."loyaltyPoint"
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int INTO loyaltyPointId;

IF loyaltyPointId IS NOT NULL THEN IF reward."rewardValue" ->> 'type' = 'absolute' THEN
SELECT
  (reward."rewardValue" ->> 'value') :: int INTO pointsToBeCredited;

ELSIF reward."rewardValue" ->> 'type' = 'conditional' THEN
SELECT
  "amount"
FROM
  "order"."cart"
WHERE
  id = (params -> 'cartId') :: int INTO cartAmount;

pointsToBeCredited := ROUND(
  cartAmount * (
    (reward."rewardValue" -> 'value' -> 'percentage') :: numeric / 100
  )
);

IF pointsToBeCredited > (reward."rewardValue" -> 'value' -> 'max') :: numeric THEN pointsToBeCredited := (reward."rewardValue" -> 'value' -> 'max') :: numeric;

END IF;

ELSE CONTINUE;

END IF;

INSERT INTO
  crm."loyaltyPointTransaction" ("loyaltyPointId", "points", "type")
VALUES
  (loyaltyPointId, pointsToBeCredited, 'CREDIT') RETURNING id INTO returnedId;

IF reward."couponId" IS NOT NULL THEN
INSERT INTO
  crm."rewardHistory"(
    "rewardId",
    "couponId",
    "keycloakId",
    "orderCartId",
    "orderId",
    "loyaltyPointTransactionId",
    "loyaltyPoints",
    "brandId"
  )
VALUES
  (
    reward.id,
    reward."couponId",
    params ->> 'keycloakId',
    (params ->> 'cartId') :: int,
    (params ->> 'orderId') :: int,
    returnedId,
    pointsToBeCredited,
    (params ->> 'brandId') :: int
  );

ELSE
INSERT INTO
  crm."rewardHistory"(
    "rewardId",
    "campaignId",
    "keycloakId",
    "orderCartId",
    "orderId",
    "loyaltyPointTransactionId",
    "loyaltyPoints",
    "brandId"
  )
VALUES
  (
    reward.id,
    reward."campaignId",
    params ->> 'keycloakId',
    (params ->> 'cartId') :: int,
    (params ->> 'orderId') :: int,
    returnedId,
    pointsToBeCredited,
    (params ->> 'brandId') :: int
  );

END IF;

END IF;

ELSIF reward."type" = 'Wallet Amount Credit' THEN
SELECT
  id
FROM
  crm."wallet"
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int INTO walletId;

IF walletId IS NOT NULL THEN IF reward."rewardValue" ->> 'type' = 'absolute' THEN
SELECT
  (reward."rewardValue" ->> 'value') :: int INTO amountToBeCredited;

ELSIF reward."rewardValue" ->> 'type' = 'conditional' THEN
SELECT
  "amount"
FROM
  "order"."cart"
WHERE
  id = (params -> 'cartId') :: int INTO cartAmount;

amountToBeCredited := ROUND(
  cartAmount * (
    (reward."rewardValue" -> 'value' -> 'percentage') :: numeric / 100
  ),
  2
);

IF amountToBeCredited > (reward."rewardValue" -> 'value' -> 'max') :: numeric THEN amountToBeCredited := (reward."rewardValue" -> 'value' -> 'max') :: numeric;

END IF;

ELSE CONTINUE;

END IF;

INSERT INTO
  crm."walletTransaction" ("walletId", "amount", "type")
VALUES
  (walletId, amountToBeCredited, 'CREDIT') RETURNING id INTO returnedId;

IF reward."couponId" IS NOT NULL THEN
INSERT INTO
  crm."rewardHistory"(
    "rewardId",
    "couponId",
    "keycloakId",
    "orderCartId",
    "orderId",
    "walletTransactionId",
    "walletAmount",
    "brandId"
  )
VALUES
  (
    reward.id,
    reward."couponId",
    params ->> 'keycloakId',
    (params ->> 'cartId') :: int,
    (params ->> 'orderId') :: int,
    returnedId,
    amountToBeCredited,
    (params ->> 'brandId') :: int
  );

ELSE
INSERT INTO
  crm."rewardHistory"(
    "rewardId",
    "campaignId",
    "keycloakId",
    "orderCartId",
    "orderId",
    "walletTransactionId",
    "walletAmount",
    "brandId"
  )
VALUES
  (
    reward.id,
    reward."campaignId",
    params ->> 'keycloakId',
    (params ->> 'cartId') :: int,
    (params ->> 'orderId') :: int,
    returnedId,
    amountToBeCredited,
    (params ->> 'brandId') :: int
  );

END IF;

END IF;

ELSIF reward."type" = 'Discount' THEN IF reward."couponId" IS NOT NULL THEN
INSERT INTO
  crm."rewardHistory"(
    "rewardId",
    "couponId",
    "keycloakId",
    "orderCartId",
    "orderId",
    "discount",
    "brandId"
  )
VALUES
  (
    reward.id,
    reward."couponId",
    params ->> 'keycloakId',
    (params ->> 'cartId') :: int,
    (params ->> 'orderId') :: int,
    (
      SELECT
        "couponDiscount"
      FROM
        "order"."cart"
      WHERE
        id = (params ->> 'cartId') :: int
    ),
    (params ->> 'brandId') :: int
  );

END IF;

ELSE CONTINUE;

END IF;

END LOOP;

END;

$ $;

CREATE FUNCTION crm."processWalletTransaction"() RETURNS trigger LANGUAGE plpgsql AS $ $ BEGIN IF NEW."type" = 'CREDIT' THEN
UPDATE
  crm."wallet"
SET
  amount = amount + NEW.amount
WHERE
  id = NEW."walletId";

ELSE
UPDATE
  crm."wallet"
SET
  amount = amount - NEW.amount
WHERE
  id = NEW."walletId";

END IF;

RETURN NULL;

END;

$ $;

CREATE
OR REPLACE FUNCTION crm."referralCampaignRewardsTriggerFunction"() RETURNS trigger LANGUAGE plpgsql AS $ function $ DECLARE params jsonb;

rewardsParams jsonb;

campaign record;

condition record;

referrerKeycloakId text;

campaignValidity boolean := false;

rewardValidity boolean;

reward record;

rewardIds int [] DEFAULT '{}';

referral record;

referralRewardGiven boolean := false;

BEGIN IF NEW."keycloakId" IS NULL THEN RETURN NULL;

END IF;

IF TG_TABLE_NAME = 'customerReferral' THEN params := jsonb_build_object(
  'keycloakId',
  NEW."keycloakId",
  'brandId',
  NEW."brandId"
);

SELECT
  "keycloakId"
FROM
  crm."customerReferral"
WHERE
  "referralCode" = NEW."referredByCode" INTO referrerKeycloakId;

ELSIF TG_TABLE_NAME = 'order' THEN params := jsonb_build_object(
  'keycloakId',
  NEW."keycloakId",
  'orderId',
  NEW.id :: int,
  'cartId',
  NEW."cartId",
  'brandId',
  NEW."brandId"
);

SELECT
  "keycloakId"
FROM
  crm."customerReferral"
WHERE
  "referralCode" = (
    SELECT
      "referredByCode"
    FROM
      crm."customerReferral"
    WHERE
      "keycloakId" = NEW."keycloakId"
  ) INTO referrerKeycloakId;

ELSE RETURN NULL;

END IF;

SELECT
  *
FROM
  crm."customerReferral"
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int INTO referral;

IF referral."referralStatus" = 'COMPLETED' THEN RETURN NULL;

END IF;

FOR campaign IN
SELECT
  *
FROM
  crm."campaign"
WHERE
  id IN (
    SELECT
      "campaignId"
    FROM
      crm."brand_campaign"
    WHERE
      "brandId" = (params -> 'brandId') :: int
      AND "isActive" = true
  )
  AND "isActive" = true
  AND "type" = 'Referral'
ORDER BY
  priority DESC,
  updated_at DESC LOOP params := params || jsonb_build_object(
    'campaignType',
    campaign."type",
    'table',
    TG_TABLE_NAME,
    'campaignId',
    campaign.id,
    'rewardId',
    null
  );

SELECT
  *
FROM
  crm."customerReferral"
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int INTO referral;

IF referral."referralStatus" = 'COMPLETED'
OR referralRewardGiven = true THEN CONTINUE;

END IF;

SELECT
  rules."isConditionValidFunc"(campaign."conditionId", params) INTO campaignValidity;

IF campaignValidity = false THEN CONTINUE;

END IF;

FOR reward IN
SELECT
  *
FROM
  crm.reward
WHERE
  "campaignId" = campaign.id
ORDER BY
  position DESC LOOP params := params || jsonb_build_object('rewardId', reward.id);

SELECT
  rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;

IF rewardValidity = true THEN IF reward."rewardValue" ->> 'type' = 'absolute'
OR (
  reward."rewardValue" ->> 'type' = 'conditional'
  AND params -> 'cartId' IS NOT NULL
) THEN rewardIds := rewardIds || reward.id;

IF campaign."isRewardMulti" = false THEN EXIT;

END IF;

END IF;

END IF;

END LOOP;

IF array_length(rewardIds, 1) > 0 THEN rewardsParams := params || jsonb_build_object(
  'campaignType',
  campaign."type",
  'keycloakId',
  referrerKeycloakId
);

PERFORM crm."processRewardsForCustomer"(rewardIds, rewardsParams);

--  create  reward history
--  trigger -> processRewardForCusotmer
UPDATE
  crm."customerReferral"
SET
  "referralCampaignId" = campaign.id,
  "referralStatus" = 'COMPLETED'
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int;

referralRewardGiven := true;

END IF;

END LOOP;

RETURN NULL;

END;

$ function $;

CREATE FUNCTION crm."rewardsTriggerFunction"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE params jsonb;

rewardsParams jsonb;

campaign record;

condition record;

campaignType text;

referrerKeycloakId text;

campaignValidity boolean := false;

rewardValidity boolean;

finalRewardValidity boolean := false;

reward record;

rewardIds int [] DEFAULT '{}';

cartId int;

referral record;

postOrderRewardGiven boolean := false;

signupRewardGiven boolean := false;

referralRewardGiven boolean := false;

BEGIN IF NEW."keycloakId" IS NULL THEN RETURN NULL;

END IF;

IF TG_TABLE_NAME = 'customerReferral' THEN -- no role of cart in referral
params := jsonb_build_object(
  'keycloakId',
  NEW."keycloakId",
  'brandId',
  NEW."brandId"
);

SELECT
  "keycloakId"
FROM
  crm."customerReferral"
WHERE
  "referralCode" = NEW."referredByCode" INTO referrerKeycloakId;

ELSIF TG_TABLE_NAME = 'order' THEN params := jsonb_build_object(
  'keycloakId',
  NEW."keycloakId",
  'orderId',
  NEW.id :: int,
  'cartId',
  NEW."cartId",
  'brandId',
  NEW."brandId"
);

ELSE RETURN NULL;

END IF;

FOR campaign IN
SELECT
  *
FROM
  crm."campaign"
WHERE
  id IN (
    SELECT
      "campaignId"
    FROM
      crm."brand_campaign"
    WHERE
      "brandId" = (params -> 'brandId') :: int
      AND "isActive" = true
  )
ORDER BY
  priority DESC,
  updated_at DESC LOOP params := params || jsonb_build_object(
    'campaignType',
    campaign."type",
    'table',
    TG_TABLE_NAME,
    'campaignId',
    campaign.id,
    'rewardId',
    null
  );

IF campaign."isActive" = false THEN -- isActive flag isn't working in query
CONTINUE;

END IF;

SELECT
  *
FROM
  crm."customerReferral"
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int INTO referral;

IF campaign."type" = 'Sign Up'
AND (
  referral."signupStatus" = 'COMPLETED'
  OR signupRewardGiven = true
) THEN CONTINUE;

END IF;

IF campaign."type" = 'Referral'
AND (
  referral."referralStatus" = 'COMPLETED'
  OR referralRewardGiven = true
  OR referral."referredByCode" IS NULL
  OR referrerKeycloakId IS NULL
) THEN CONTINUE;

END IF;

IF campaign."type" = 'Post Order'
AND (
  params ->> 'cartId' IS NULL
  OR postOrderRewardGiven = true
) THEN CONTINUE;

END IF;

SELECT
  rules."isConditionValidFunc"(campaign."conditionId", params) INTO campaignValidity;

IF campaignValidity = false THEN CONTINUE;

END IF;

FOR reward IN
SELECT
  *
FROM
  crm.reward
WHERE
  "campaignId" = campaign.id
ORDER BY
  priority DESC LOOP params := params || jsonb_build_object('rewardId', reward.id);

SELECT
  rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;

IF rewardValidity = true THEN rewardIds := rewardIds || reward.id;

IF campaign."isRewardMulti" = false THEN finalRewardValidity := finalRewardValidity
OR rewardValidity;

EXIT;

END IF;

END IF;

finalRewardValidity := finalRewardValidity
OR rewardValidity;

END LOOP;

IF finalRewardValidity = true
AND array_length(rewardIds, 1) > 0 THEN rewardsParams := params || jsonb_build_object('campaignType', campaign."type");

IF campaign."type" = 'Referral' THEN -- reward should be given to referrer
rewardsParams := params || jsonb_build_object('keycloakId', referrerKeycloakId);

END IF;

PERFORM crm."processRewardsForCustomer"(rewardIds, rewardsParams);

IF campaign."type" = 'Sign Up' THEN
UPDATE
  crm."customerReferral"
SET
  "signupCampaignId" = campaign.id,
  "signupStatus" = 'COMPLETED'
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int;

signupRewardGiven := true;

ELSIF campaign."type" = 'Referral' THEN
UPDATE
  crm."customerReferral"
SET
  "referralCampaignId" = campaign.id,
  "referralStatus" = 'COMPLETED'
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int;

referralRewardGiven := true;

ELSIF campaign."type" = 'Post Order' THEN postOrderRewardGiven := true;

ELSE CONTINUE;

END IF;

END IF;

END LOOP;

RETURN NULL;

END;

$ $;

CREATE FUNCTION crm."setLoyaltyPointsUsedInCart"(cartid integer, points integer) RETURNS void LANGUAGE plpgsql AS $ $ BEGIN
UPDATE
  "order"."cart"
SET
  "loyaltyPointsUsed" = points
WHERE
  id = cartid;

END $ $;

CREATE TABLE public.response (
  success boolean NOT NULL,
  message text NOT NULL
);

CREATE FUNCTION crm."setReferralCode"(params jsonb) RETURNS SETOF public.response LANGUAGE plpgsql STABLE AS $ $ DECLARE rec record;

kId text;

code text;

success boolean := true;

message text := 'Referral code applied!';

BEGIN
SELECT
  "referredByCode"
FROM
  crm."customerReferral"
WHERE
  "referralCode" = (params ->> 'referralCode') :: text
  AND "brandId" = (params ->> 'brandId') :: int INTO code;

IF code IS NOT NULL THEN -- case when code is already applied
success := false;

message := 'Referral code already applied!';

ELSE IF params ->> 'input' LIKE '%@%' THEN
SELECT
  "keycloakId"
FROM
  crm.customer
WHERE
  email = params ->> 'input' INTO kId;

SELECT
  *
FROM
  crm.brand_customer
WHERE
  "keycloakId" = kId
  AND "brandId" = (params ->> 'brandId') :: int INTO rec;

IF rec IS NULL THEN success := false;

message := 'Incorrect email!';

END IF;

IF kId IS NOT NULL THEN
SELECT
  "referralCode"
FROM
  crm."customerReferral"
WHERE
  "keycloakId" = kId
  AND "brandId" = (params ->> 'brandId') :: int INTO code;

IF code IS NOT NULL
AND code != params ->> 'referralCode' THEN PERFORM "crm"."updateReferralCode"(
  (params ->> 'referralCode') :: text,
  code :: text
);

ELSE success := false;

message := 'Incorrect email!';

END IF;

ELSE success := false;

message := 'Incorrect email!';

END IF;

ELSE
SELECT
  "referralCode"
FROM
  crm."customerReferral"
WHERE
  "referralCode" = (params ->> 'input') :: text
  AND "brandId" = (params ->> 'brandId') :: int INTO code;

IF code is NOT NULL
AND code != params ->> 'referralCode' THEN PERFORM "crm"."updateReferralCode"(
  (params ->> 'referralCode') :: text,
  code :: text
);

ELSE success := false;

message := 'Incorrect referral code!';

END IF;

END IF;

END IF;

RETURN QUERY
SELECT
  success AS success,
  message AS message;

END;

$ $;

CREATE FUNCTION crm."setWalletAmountUsedInCart"(cartid integer, validamount numeric) RETURNS void LANGUAGE plpgsql AS $ $ BEGIN
UPDATE
  "order"."cart"
SET
  "walletAmountUsed" = validAmount
WHERE
  id = cartId;

END $ $;

CREATE FUNCTION crm.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE
OR REPLACE FUNCTION crm."signUpCampaignRewardsTriggerFunction"() RETURNS trigger LANGUAGE plpgsql AS $ function $ DECLARE params jsonb;

rewardsParams jsonb;

campaign record;

condition record;

referrerKeycloakId text;

campaignValidity boolean := false;

rewardValidity boolean;

reward record;

rewardIds int [] DEFAULT '{}';

referral record;

signupRewardGiven boolean := false;

BEGIN IF NEW."keycloakId" IS NULL THEN RETURN NULL;

END IF;

IF TG_TABLE_NAME = 'customerReferral' THEN params := jsonb_build_object(
  'keycloakId',
  NEW."keycloakId",
  'brandId',
  NEW."brandId"
);

SELECT
  "keycloakId"
FROM
  crm."customerReferral"
WHERE
  "referralCode" = NEW."referredByCode" INTO referrerKeycloakId;

ELSIF TG_TABLE_NAME = 'order' THEN params := jsonb_build_object(
  'keycloakId',
  NEW."keycloakId",
  'orderId',
  NEW.id :: int,
  'cartId',
  NEW."cartId",
  'brandId',
  NEW."brandId"
);

ELSE RETURN NULL;

END IF;

SELECT
  *
FROM
  crm."customerReferral"
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int INTO referral;

IF referral."signupStatus" = 'COMPLETED' THEN RETURN NULL;

END IF;

FOR campaign IN
SELECT
  *
FROM
  crm."campaign"
WHERE
  id IN (
    SELECT
      "campaignId"
    FROM
      crm."brand_campaign"
    WHERE
      "brandId" = (params -> 'brandId') :: int
      AND "isActive" = true
  )
  AND "isActive" = true
  AND "type" = 'Sign Up'
ORDER BY
  priority DESC,
  updated_at DESC LOOP params := params || jsonb_build_object(
    'campaignType',
    campaign."type",
    'table',
    TG_TABLE_NAME,
    'campaignId',
    campaign.id,
    'rewardId',
    null
  );

SELECT
  *
FROM
  crm."customerReferral"
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int INTO referral;

IF referral."signupStatus" = 'COMPLETED'
OR signupRewardGiven = true THEN CONTINUE;

END IF;

SELECT
  rules."isConditionValidFunc"(campaign."conditionId", params) INTO campaignValidity;

IF campaignValidity = false THEN CONTINUE;

END IF;

FOR reward IN
SELECT
  *
FROM
  crm.reward
WHERE
  "campaignId" = campaign.id
ORDER BY
  position DESC LOOP params := params || jsonb_build_object('rewardId', reward.id);

SELECT
  rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;

IF rewardValidity = true THEN IF reward."rewardValue" ->> 'type' = 'absolute'
OR (
  reward."rewardValue" ->> 'type' = 'conditional'
  AND params -> 'cartId' IS NOT NULL
) THEN rewardIds := rewardIds || reward.id;

IF campaign."isRewardMulti" = false THEN EXIT;

END IF;

END IF;

END IF;

END LOOP;

IF array_length(rewardIds, 1) > 0 THEN rewardsParams := params || jsonb_build_object('campaignType', campaign."type");

PERFORM crm."processRewardsForCustomer"(rewardIds, rewardsParams);

UPDATE
  crm."customerReferral"
SET
  "signupCampaignId" = campaign.id,
  "signupStatus" = 'COMPLETED'
WHERE
  "keycloakId" = params ->> 'keycloakId'
  AND "brandId" = (params ->> 'brandId') :: int;

signupRewardGiven := true;

END IF;

END LOOP;

RETURN NULL;

END;

$ function $;

CREATE FUNCTION crm."updateBrand_customer"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE BEGIN
UPDATE
  "crm"."brand_customer"
SET
  "subscriptionTitleId" = (
    select
      "subscriptionTitleId"
    from
      "subscription"."subscription"
    where
      id = NEW."subscriptionId"
  ),
  "subscriptionServingId" = (
    select
      "subscriptionServingId"
    from
      "subscription"."subscription"
    where
      id = NEW."subscriptionId"
  ),
  "subscriptionItemCountId" = (
    select
      "subscriptionItemCountId"
    from
      "subscription"."subscription"
    where
      id = NEW."subscriptionId"
  )
WHERE
  id = NEW.id;

RETURN null;

END;

$ $;

CREATE FUNCTION crm."updateReferralCode"(referralcode text, referredbycode text) RETURNS void LANGUAGE plpgsql AS $ $ BEGIN
UPDATE
  crm."customerReferral"
SET
  "referredByCode" = referredByCode
WHERE
  "referralCode" = referralCode;

END;

$ $;

CREATE FUNCTION crm.updateissubscribertimestamp() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE BEGIN IF NEW."isSubscriber" = true
and old."isSubscriber" = false THEN
update
  "crm"."brand_customer"
set
  "isSubscriberTimeStamp" = now();

END IF;

RETURN NULL;

END;

$ $;

CREATE FUNCTION "deviceHub".set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE TABLE editor."priorityFuncTable" (id integer NOT NULL);

CREATE FUNCTION editor."HandlePriority4"(arg jsonb) RETURNS SETOF editor."priorityFuncTable" LANGUAGE plpgsql STABLE AS $ $ DECLARE currentdata jsonb;

datalist jsonb := '[]';

tablenameinput text;

schemanameinput text;

currentdataid int;

currentdataposition numeric;

columnToBeUpdated text;

BEGIN datalist := arg ->> 'data1';

schemanameinput := arg ->> 'schemaname';

tablenameinput := arg ->> 'tablename';

columnToBeUpdated := COALESCE(arg ->> 'column', 'position');

IF arg IS NOT NULL THEN FOR currentdata IN
SELECT
  *
FROM
  jsonb_array_elements(datalist) LOOP currentdataid := currentdata ->> 'id';

currentdataposition := currentdata ->> columnToBeUpdated;

PERFORM editor."updatePriorityFinal"(
  tablenameinput,
  schemanameinput,
  currentdataid,
  currentdataposition,
  columnToBeUpdated
);

END LOOP;

END IF;

RETURN QUERY
SELECT
  1 AS id;

END;

$ $;

CREATE FUNCTION editor.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE FUNCTION editor."updatePriorityFinal"(
  tablename text,
  schemaname text,
  id integer,
  pos numeric,
  col text
) RETURNS record LANGUAGE plpgsql AS $ $ DECLARE data record;

querystring text := '';

BEGIN querystring := 'UPDATE ' || '"' || schemaname || '"' || '.' || '"' || tablename || '"' || 'set ' || col || ' =' || pos || 'where "id" =' || id || ' returning *';

EXECUTE querystring into data;

RETURN data;

END;

$ $;

CREATE TABLE fulfilment."mileRange" (
  id integer DEFAULT public.defaultid(
    'fulfilment' :: text,
    'mileRange' :: text,
    'id' :: text
  ) NOT NULL,
  "from" numeric,
  "to" numeric,
  "leadTime" integer,
  "prepTime" integer,
  "isActive" boolean DEFAULT true NOT NULL,
  "timeSlotId" integer,
  zipcodes jsonb
);

CREATE FUNCTION fulfilment."preOrderDeliveryValidity"(
  milerange fulfilment."mileRange",
  "time" time without time zone
) RETURNS boolean LANGUAGE plpgsql STABLE AS $ $ DECLARE fromVal time;

toVal time;

BEGIN
SELECT
  "from" into fromVal
FROM
  fulfilment."timeSlot"
WHERE
  id = mileRange."timeSlotId";

SELECT
  "to" into toVal
FROM
  fulfilment."timeSlot"
WHERE
  id = mileRange."timeSlotId";

RETURN true;

END $ $;

CREATE TABLE fulfilment."timeSlot" (
  id integer DEFAULT public.defaultid(
    'fulfilment' :: text,
    'timeSlot' :: text,
    'id' :: text
  ) NOT NULL,
  "recurrenceId" integer,
  "isActive" boolean DEFAULT true NOT NULL,
  "from" time without time zone,
  "to" time without time zone,
  "pickUpLeadTime" integer DEFAULT 120,
  "pickUpPrepTime" integer DEFAULT 30
);

CREATE FUNCTION fulfilment."preOrderPickupTimeFrom"(timeslot fulfilment."timeSlot") RETURNS time without time zone LANGUAGE plpgsql STABLE AS $ $ -- SELECT "from".timeslot AS fromtime, "pickupLeadTime".timeslot AS buffer, diff(fromtime, buffer) as "pickupFromTime"
BEGIN return ("from".timeslot - "pickupLeadTime".timeslot);

END $ $;

CREATE FUNCTION fulfilment."preOrderPickupValidity"(
  timeslot fulfilment."timeSlot",
  "time" time without time zone
) RETURNS boolean LANGUAGE plpgsql STABLE AS $ $ BEGIN -- IF JSONB_ARRAY_LENGTH(ordercart."cartInfo"->'products') = 0
--     THEN RETURN json_build_object('status', false, 'error', 'No items in cart!');
-- ELSIF ordercart."paymentMethodId" IS NULL OR ordercart."stripeCustomerId" IS NULL
--     THEN RETURN json_build_object('status', false, 'error', 'No payment method selected!');
-- ELSIF ordercart."address" IS NULL
--     THEN RETURN json_build_object('status', false, 'error', 'No address selected!');
-- ELSE
RETURN true;

-- END IF;
END $ $;

CREATE FUNCTION fulfilment.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE FUNCTION ingredient."MOFCost"(mofid integer) RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE mof record;

bulkItemId int;

supplierItemId int;

supplierItem record;

costs jsonb;

BEGIN
SELECT
  *
FROM
  ingredient."modeOfFulfillment"
WHERE
  id = mofId into mof;

IF mof."bulkItemId" IS NOT NULL THEN
SELECT
  mof."bulkItemId" into bulkItemId;

ELSE
SELECT
  bulkItemId
FROM
  inventory."sachetItem"
WHERE
  id = mof."sachetItemId" into bulkItemId;

END IF;

SELECT
  "supplierItemId"
FROM
  inventory."bulkItem"
WHERE
  id = bulkItemId into supplierItemId;

SELECT
  *
FROM
  inventory."supplierItem"
WHERE
  id = supplierItemId into supplierItem;

IF supplierItem.prices IS NULL
OR supplierItem.prices -> 0 -> 'unitPrice' ->> 'value' = '' THEN RETURN 0;

ELSE RETURN (
  supplierItem.prices -> 0 -> 'unitPrice' ->> 'value'
) :: numeric / supplierItem."unitSize";

END IF;

END $ $;

CREATE FUNCTION ingredient."MOFNutritionalInfo"(mofid integer) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE info jsonb;

mof record;

bulkItemId int;

BEGIN
SELECT
  *
FROM
  ingredient."modeOfFulfillment"
WHERE
  id = mofId into mof;

IF mof."bulkItemId" IS NOT NULL THEN
SELECT
  "nutritionInfo"
FROM
  inventory."bulkItem"
WHERE
  id = mof."bulkItemId" into info;

RETURN info;

ELSE
SELECT
  bulkItemId
FROM
  inventory."sachetItem"
WHERE
  id = mof."sachetItemId" into bulkItemId;

SELECT
  "nutritionInfo"
FROM
  inventory."bulkItem"
WHERE
  id = bulkItemId into info;

RETURN info;

END IF;

END $ $;

CREATE TABLE ingredient."ingredientSachet" (
  id integer DEFAULT public.defaultid(
    'ingredient' :: text,
    'ingredientSachet' :: text,
    'id' :: text
  ) NOT NULL,
  quantity numeric NOT NULL,
  "ingredientProcessingId" integer NOT NULL,
  "ingredientId" integer NOT NULL,
  "createdAt" timestamp with time zone DEFAULT now(),
  "updatedAt" timestamp with time zone DEFAULT now(),
  tracking boolean DEFAULT true NOT NULL,
  unit text NOT NULL,
  visibility boolean DEFAULT true NOT NULL,
  "liveMOF" integer,
  "isArchived" boolean DEFAULT false NOT NULL
);

CREATE FUNCTION ingredient.cost(sachet ingredient."ingredientSachet") RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE cost numeric;

BEGIN
SELECT
  ingredient."sachetCost"(sachet.id) into cost;

RETURN cost;

END $ $;

CREATE TABLE ingredient."modeOfFulfillment" (
  id integer DEFAULT public.defaultid(
    'ingredient' :: text,
    'modeOfFulfillment' :: text,
    'id' :: text
  ) NOT NULL,
  type text NOT NULL,
  "stationId" integer,
  "labelTemplateId" integer,
  "bulkItemId" integer,
  "isPublished" boolean DEFAULT false NOT NULL,
  "position" numeric,
  "ingredientSachetId" integer NOT NULL,
  "packagingId" integer,
  "isLive" boolean DEFAULT false NOT NULL,
  accuracy integer,
  "sachetItemId" integer,
  "operationConfigId" integer,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  priority integer DEFAULT 1 NOT NULL,
  "ingredientId" integer,
  "ingredientProcessingId" integer
);

CREATE FUNCTION ingredient."getMOFCost"(mof ingredient."modeOfFulfillment") RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE cost numeric;

BEGIN
SELECT
  ingredient."MOFCost"(mof.id) into cost;

RETURN cost;

END $ $;

CREATE FUNCTION ingredient."getMOFNutritionalInfo"(mof ingredient."modeOfFulfillment") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE info jsonb;

BEGIN
SELECT
  ingredient."MOFNutritionalInfo"(mof.id) into info;

RETURN info;

END $ $;

CREATE TABLE ingredient.ingredient (
  id integer DEFAULT public.defaultid(
    'ingredient' :: text,
    'ingredient' :: text,
    'id' :: text
  ) NOT NULL,
  name text NOT NULL,
  image text,
  "isPublished" boolean DEFAULT false NOT NULL,
  category text,
  "createdAt" date DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  "isArchived" boolean DEFAULT false NOT NULL,
  assets jsonb
);

CREATE FUNCTION ingredient.image_validity(ing ingredient.ingredient) RETURNS boolean LANGUAGE sql STABLE AS $ $
SELECT
  NOT(ing.image IS NULL) $ $;

CREATE FUNCTION ingredient.imagevalidity(image ingredient.ingredient) RETURNS boolean LANGUAGE sql STABLE AS $ $
SELECT
  NOT(image.image IS NULL) $ $;

CREATE FUNCTION ingredient.isingredientvalid(ingredient ingredient.ingredient) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE temp jsonb;

BEGIN
SELECT
  *
FROM
  ingredient."ingredientSachet"
where
  "ingredientId" = ingredient.id
LIMIT
  1 into temp;

IF temp IS NULL THEN return json_build_object('status', false, 'error', 'Not sachet present');

ELSIF ingredient.category IS NULL THEN return json_build_object(
  'status',
  false,
  'error',
  'Category not provided'
);

ELSIF ingredient.image IS NULL
OR LENGTH(ingredient.image) = 0 THEN return json_build_object('status', true, 'error', 'Image not provided');

ELSE return json_build_object('status', true, 'error', '');

END IF;

END $ $;

CREATE FUNCTION ingredient.ismodevalid(mode ingredient."modeOfFulfillment") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE temp json;

isSachetValid boolean;

BEGIN
SELECT
  ingredient.isSachetValid("ingredientSachet".*)
FROM
  ingredient."ingredientSachet"
WHERE
  "ingredientSachet".id = mode."ingredientSachetId" into temp;

SELECT
  temp -> 'status' into isSachetValid;

IF NOT isSachetValid THEN return json_build_object('status', false, 'error', 'Sachet is not valid');

ELSIF mode."stationId" IS NULL THEN return json_build_object(
  'status',
  false,
  'error',
  'Station is not provided'
);

ELSIF mode."bulkItemId" IS NULL
AND mode."sachetItemId" IS NULL THEN return json_build_object('status', false, 'error', 'Item is not provided');

ELSE return json_build_object('status', true, 'error', '');

END IF;

END $ $;

CREATE FUNCTION ingredient.issachetvalid(sachet ingredient."ingredientSachet") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE temp json;

isIngredientValid boolean;

BEGIN
SELECT
  ingredient.isIngredientValid(ingredient.*)
FROM
  ingredient.ingredient
where
  ingredient.id = sachet."ingredientId" into temp;

SELECT
  temp -> 'status' into isIngredientValid;

IF NOT isIngredientValid THEN return json_build_object(
  'status',
  false,
  'error',
  'Ingredient is not valid'
);

-- ELSIF sachet."defaultNutritionalValues" IS NULL
--     THEN return json_build_object('status', true, 'error', 'Default nutritional values not provided');
ELSE return json_build_object('status', true, 'error', '');

END IF;

END $ $;

CREATE TABLE "simpleRecipe"."simpleRecipe" (
  id integer DEFAULT public.defaultid(
    'simpleRecipe' :: text,
    'simpleRecipe' :: text,
    'id' :: text
  ) NOT NULL,
  author text,
  name jsonb NOT NULL,
  "cookingTime" text,
  utensils jsonb,
  description text,
  cuisine text,
  image text,
  show boolean DEFAULT true NOT NULL,
  assets jsonb,
  type text,
  "isPublished" boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  "isArchived" boolean DEFAULT false NOT NULL,
  "notIncluded" jsonb,
  "showIngredients" boolean DEFAULT true NOT NULL,
  "showIngredientsQuantity" boolean DEFAULT true NOT NULL,
  "showProcedures" boolean DEFAULT true NOT NULL,
  "isSubRecipe" boolean
);

CREATE FUNCTION ingredient.issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE BEGIN -- SELECT ingredient.isSachetValid("ingredientSachet".*) 
--     FROM ingredient."ingredientSachet"
--     WHERE "ingredientSachet".id = mode."ingredientSachetId" into temp;
-- SELECT temp->'status' into isSachetValid;
IF recipe.utensils IS NULL
OR ARRAY_LENGTH(recipe.utensils) = 0 THEN return json_build_object(
  'status',
  false,
  'error',
  'Utensils not provided'
);

ELSIF recipe.procedures IS NULL
OR ARRAY_LENGTH(recipe.procedures) = 0 THEN return json_build_object(
  'status',
  false,
  'error',
  'Cooking steps are not provided'
);

ELSIF recipe.ingredients IS NULL
OR ARRAY_LENGTH(recipe.ingredients) = 0 THEN return json_build_object(
  'status',
  false,
  'error',
  'Ingrdients are not provided'
);

ELSE return json_build_object('status', true, 'error', '');

END IF;

END $ $;

CREATE FUNCTION ingredient."nutritionalInfo"(sachet ingredient."ingredientSachet") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE info jsonb;

BEGIN
SELECT
  ingredient."sachetNutritionalInfo"(sachet.id) into info;

RETURN info;

END $ $;

CREATE FUNCTION ingredient."sachetCost"(sachetid integer) RETURNS numeric LANGUAGE plpgsql STABLE AS $ $ DECLARE sachet record;

mofId int;

temp numeric;

BEGIN
SELECT
  *
FROM
  ingredient."ingredientSachet"
WHERE
  id = sachetId INTO sachet;

SELECT
  id
FROM
  ingredient."modeOfFulfillment"
WHERE
  "ingredientSachetId" = sachetId
ORDER BY
  COALESCE(position, id) DESC
LIMIT
  1 INTO mofId;

SELECT
  ingredient."MOFCost"(mofId) INTO temp;

IF temp IS NULL
OR temp = 0 THEN
SELECT
  "cost" -> 'value'
FROM
  ingredient."ingredientProcessing"
WHERE
  id = sachet."ingredientProcessingId" INTO temp;

END IF;

IF temp IS NULL THEN RETURN 0;

ELSE RETURN temp * sachet.quantity;

END IF;

END $ $;

CREATE FUNCTION ingredient."sachetNutritionalInfo"(sachet ingredient."ingredientSachet") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE info jsonb;

BEGIN
SELECT
  "nutritionalInfo"
FROM
  ingredient."ingredientProcessing"
WHERE
  id = sachet."ingredientProcessingId" into info;

RETURN info;

END $ $;

CREATE FUNCTION ingredient."sachetNutritionalInfo"(sachetid integer) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE info jsonb;

sachet record;

mofId int;

per numeric;

BEGIN
SELECT
  *
FROM
  ingredient."ingredientSachet"
WHERE
  id = sachetId INTO sachet;

-- order by position and not id
SELECT
  id
FROM
  ingredient."modeOfFulfillment"
WHERE
  "ingredientSachetId" = sachetId
ORDER BY
  id DESC NULLS LAST
LIMIT
  1 INTO mofId;

SELECT
  ingredient."MOFNutritionalInfo"(mofId) INTO info;

IF info IS NULL THEN
SELECT
  "nutritionalInfo"
FROM
  ingredient."ingredientProcessing"
WHERE
  id = sachet."ingredientProcessingId" INTO info;

END IF;

IF info IS NULL THEN RETURN info;

ELSE
SELECT
  COALESCE((info ->> 'per') :: numeric, 1) into per;

RETURN json_build_object(
  'per',
  per,
  'iron',
  COALESCE((info ->> 'iron') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'sodium',
  COALESCE((info ->> 'sodium') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'sugars',
  COALESCE((info ->> 'sugars') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'calcium',
  COALESCE((info ->> 'calcium') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'protein',
  COALESCE((info ->> 'protein') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'calories',
  COALESCE((info ->> 'calories') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'totalFat',
  COALESCE((info ->> 'totalFat') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'transFat',
  COALESCE((info ->> 'transFat') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'vitaminA',
  COALESCE((info ->> 'vitaminA') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'vitaminC',
  COALESCE((info ->> 'vitaminC') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'cholesterol',
  COALESCE((info ->> 'cholesterol') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'dietaryFibre',
  COALESCE((info ->> 'dietaryFibre') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'saturatedFat',
  COALESCE((info ->> 'saturatedFat') :: numeric, 0) * (sachet.quantity) :: numeric / per,
  'totalCarbohydrates',
  COALESCE((info ->> 'totalCarbohydrates') :: numeric, 0) * (sachet.quantity) :: numeric / per
);

END IF;

END $ $;

CREATE FUNCTION ingredient.sachetvalidity(sachet ingredient."ingredientSachet") RETURNS boolean LANGUAGE sql STABLE AS $ $
SELECT
  NOT(
    sachet.unit IS NULL
    OR sachet.quantity <= 0
  ) $ $;

CREATE FUNCTION ingredient."set_current_timestamp_updatedAt"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updatedAt" = NOW();

RETURN _new;

END;

$ $;

CREATE FUNCTION ingredient.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE FUNCTION ingredient.twiceq(sachet ingredient."ingredientSachet") RETURNS numeric LANGUAGE sql STABLE AS $ $
SELECT
  sachet.quantity * 2 $ $;

CREATE FUNCTION ingredient."updateModeOfFulfillment"() RETURNS trigger LANGUAGE plpgsql AS $ $ BEGIN
update
  "ingredient"."modeOfFulfillment"
SET
  "ingredientId" = (
    select
      "ingredientId"
    from
      "ingredient"."ingredientSachet"
    where
      id = NEW."ingredientSachetId"
  ),
  "ingredientProcessingId" = (
    select
      "ingredientProcessingId"
    from
      "ingredient"."ingredientSachet"
    where
      id = NEW."ingredientSachetId"
  );

RETURN NULL;

END;

$ $;

CREATE FUNCTION ingredient.validity(sachet ingredient."ingredientSachet") RETURNS boolean LANGUAGE sql STABLE AS $ $
SELECT
  NOT(
    sachet.unit IS NULL
    OR sachet.quantity <= 0
  ) $ $;

CREATE FUNCTION insights.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE FUNCTION inventory."customToCustomUnitConverter"(
  quantity numeric,
  unit_id integer,
  bulkdensity numeric DEFAULT 1,
  unit_to_id integer DEFAULT NULL :: integer
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE from_custom_rule record;

to_custom_rule record;

result jsonb := '{"error": null, "result": null}' :: jsonb;

proceed text := NULL;

from_in_standard jsonb;

BEGIN
SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  id = unit_to_id into to_custom_rule;

SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  id = unit_id into from_custom_rule;

IF to_custom_rule IS NULL THEN proceed := 'to_unit';

ELSEIF from_custom_rule IS NULL THEN proceed := 'from_unit';

END IF;

IF proceed IS NULL THEN
SELECT
  data -> 'result' -> 'custom' -> from_custom_rule.input_unit
FROM
  inventory."unitVariationFunc"(
    quantity,
    from_custom_rule.input_unit,
    (-1) :: numeric,
    to_custom_rule.output_unit :: text,
    unit_id
  ) INTO from_in_standard;

SELECT
  data
FROM
  inventory."standardToCustomUnitConverter"(
    (from_in_standard -> 'equivalentValue') :: numeric,
    (from_in_standard ->> 'toUnitName') :: text,
    (-1) :: numeric,
    unit_to_id
  ) INTO result;

result := jsonb_build_object(
  'error',
  'null' :: jsonb,
  'result',
  jsonb_build_object(
    'value',
    quantity,
    'toUnitName',
    to_custom_rule.input_unit,
    'fromUnitName',
    from_custom_rule.input_unit,
    'equivalentValue',
    (result -> 'result' -> 'equivalentValue') :: numeric
  )
);

ELSEIF proceed = 'to_unit' THEN result := format(
  '{"error": "no custom unit is defined with the id: %s for argument to_unit, create a conversion rule in the master.\"unitConversion\" table."}',
  unit_to_id
) :: jsonb;

ELSEIF proceed = 'from_unit' THEN result := format(
  '{"error": "no custom unit is defined with the id: %s for argument from_unit, create a conversion rule in the master.\"unitConversion\" table."}',
  unit_id
) :: jsonb;

END IF;

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory."customToCustomUnitConverter"(
  quantity numeric,
  unit text,
  bulkdensity numeric DEFAULT 1,
  unitto text DEFAULT NULL :: text
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE from_custom_rule record;

to_custom_rule record;

result jsonb := '{"error": null, "result": null}' :: jsonb;

proceed text := NULL;

from_in_standard jsonb;

BEGIN
SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  "inputUnitName" = unitTo into to_custom_rule;

SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  "inputUnitName" = unit into from_custom_rule;

IF to_custom_rule IS NULL THEN proceed := 'to_unit';

ELSEIF from_custom_rule IS NULL THEN proceed := 'from_unit';

END IF;

IF proceed IS NULL THEN
SELECT
  data -> 'result' -> 'custom' -> unit
FROM
  inventory."unitVariationFunc"(
    'tablename',
    quantity,
    unit,
    -1,
    to_custom_rule.output_unit :: text
  ) INTO from_in_standard;

SELECT
  data
FROM
  inventory."standardToCustomUnitConverter"(
    (from_in_standard -> 'equivalentValue') :: numeric,
    (from_in_standard ->> 'toUnitName') :: text,
    -1,
    unitTo
  ) INTO result;

result := jsonb_build_object(
  'error',
  'null' :: jsonb,
  'result',
  jsonb_build_object(
    'value',
    quantity,
    'toUnitName',
    unitTo,
    'fromUnitName',
    unit,
    'equivalentValue',
    (result -> 'result' -> 'equivalentValue') :: numeric
  )
);

ELSEIF proceed = 'to_unit' THEN result := format(
  '{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}',
  unitTo :: text
) :: jsonb;

ELSEIF proceed = 'from_unit' THEN result := format(
  '{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}',
  unit :: text
) :: jsonb;

END IF;

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory."customUnitVariationFunc"(
  quantity numeric,
  unit_id integer,
  tounit text DEFAULT NULL :: text
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE result jsonb;

custom_conversions jsonb;

standard_conversions jsonb;

custom_unit_definition record;

BEGIN
SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  id = unit_id into custom_unit_definition;

If custom_unit_definition IS NOT NULL THEN custom_conversions := jsonb_build_object(
  custom_unit_definition.input_unit,
  jsonb_build_object(
    'value',
    quantity,
    'toUnitName',
    custom_unit_definition.output_unit,
    'fromUnitName',
    custom_unit_definition.input_unit,
    'equivalentValue',
    quantity * custom_unit_definition.conversion_factor
  )
);

SELECT
  data -> 'result' -> 'standard'
FROM
  inventory."unitVariationFunc"(
    quantity * custom_unit_definition.conversion_factor,
    custom_unit_definition.output_unit,
    -1,
    toUnit
  ) INTO standard_conversions;

ELSE result := format(
  '{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}',
  custom_unit_definition.input_unit
) :: jsonb;

END IF;

result := jsonb_build_object(
  'error',
  result ->> 'error',
  'result',
  jsonb_build_object(
    'custom',
    custom_conversions,
    'standard',
    standard_conversions
  )
);

RETURN QUERY
SELECT
  1 as id,
  result as data;

END $ $;

CREATE FUNCTION inventory."customUnitVariationFunc"(
  quantity numeric,
  customunit text,
  tounit text DEFAULT NULL :: text
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE result jsonb;

custom_conversions jsonb;

standard_conversions jsonb;

custom_unit_definition record;

BEGIN
SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  "inputUnitName" = customUnit into custom_unit_definition;

If custom_unit_definition IS NOT NULL THEN custom_conversions := jsonb_build_object(
  customUnit,
  jsonb_build_object(
    'value',
    quantity,
    'toUnitName',
    custom_unit_definition.output_unit,
    'fromUnitName',
    custom_unit_definition.input_unit,
    'equivalentValue',
    quantity * custom_unit_definition.conversion_factor
  )
);

SELECT
  data -> 'result' -> 'standard'
FROM
  inventory."unitVariationFunc"(
    'tablename',
    quantity * custom_unit_definition.conversion_factor,
    custom_unit_definition.output_unit,
    -1,
    toUnit
  ) INTO standard_conversions;

ELSE result := format(
  '{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}',
  customUnit
) :: jsonb;

END IF;

result := jsonb_build_object(
  'error',
  result ->> 'error',
  'result',
  jsonb_build_object(
    'custom',
    custom_conversions,
    'standard',
    standard_conversions
  )
);

RETURN QUERY
SELECT
  1 as id,
  result as data;

END $ $;

CREATE FUNCTION inventory.custom_to_custom_unit_converter(
  quantity numeric,
  from_unit text,
  from_bulk_density numeric,
  to_unit text,
  to_unit_bulk_density numeric,
  from_unit_id integer,
  to_unit_id integer
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE from_custom_rule record;

to_custom_rule record;

result jsonb := '{"error": null, "result": null}' :: jsonb;

proceed text := NULL;

from_in_standard jsonb;

BEGIN
SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  id = to_unit_id into to_custom_rule;

SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  id = from_unit_id into from_custom_rule;

IF to_custom_rule IS NULL THEN proceed := 'to_unit';

ELSEIF from_custom_rule IS NULL THEN proceed := 'from_unit';

END IF;

IF proceed IS NULL THEN
SELECT
  data -> 'result' -> 'custom' -> from_custom_rule.input_unit
FROM
  inventory.custom_to_standard_unit_converter(
    quantity,
    from_custom_rule.input_unit,
    from_bulk_density,
    to_custom_rule.output_unit :: text,
    to_unit_bulk_density,
    from_unit_id,
    '',
    '',
    0
  ) INTO from_in_standard;

SELECT
  data
FROM
  inventory.standard_to_custom_unit_converter(
    (from_in_standard -> 'equivalentValue') :: numeric,
    (from_in_standard ->> 'toUnitName') :: text,
    from_bulk_density,
    to_unit,
    to_unit_bulk_density,
    to_unit_id
  ) INTO result;

result := jsonb_build_object(
  'error',
  'null' :: jsonb,
  'result',
  jsonb_build_object(
    'value',
    quantity,
    'toUnitName',
    to_unit,
    'fromUnitName',
    from_unit,
    'equivalentValue',
    (result -> 'result' -> 'equivalentValue') :: numeric
  )
);

ELSEIF proceed = 'to_unit' THEN result := format(
  '{"error": "no custom unit is defined with the id: %s for argument to_unit, create a conversion rule in the master.\"unitConversion\" table."}',
  to_unit_id
) :: jsonb;

ELSEIF proceed = 'from_unit' THEN result := format(
  '{"error": "no custom unit is defined with the id: %s for argument from_unit, create a conversion rule in the master.\"unitConversion\" table."}',
  from_unit_id
) :: jsonb;

END IF;

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory.custom_to_standard_unit_converter(
  quantity numeric,
  from_unit text,
  from_bulk_density numeric,
  to_unit text,
  to_unit_bulk_density numeric,
  unit_conversion_id integer,
  schemaname text,
  tablename text,
  entity_id integer
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE result jsonb;

custom_conversions jsonb;

standard_conversions jsonb;

custom_unit_definition record;

BEGIN
SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  id = unit_conversion_id into custom_unit_definition;

If custom_unit_definition IS NOT NULL THEN custom_conversions := jsonb_build_object(
  custom_unit_definition.input_unit,
  jsonb_build_object(
    'value',
    quantity,
    'toUnitName',
    custom_unit_definition.output_unit,
    'fromUnitName',
    custom_unit_definition.input_unit,
    'equivalentValue',
    quantity * custom_unit_definition.conversion_factor
  )
);

SELECT
  data -> 'result'
FROM
  inventory.standard_to_standard_unit_converter(
    quantity * custom_unit_definition.conversion_factor,
    custom_unit_definition.output_unit,
    from_bulk_density,
    to_unit,
    to_unit_bulk_density,
    schemaname,
    tablename,
    entity_id,
    'all'
  ) INTO standard_conversions;

ELSE result := format(
  '{"error": "no custom unit is defined with the id: %s and name: %s, create a conversion rule in the master.\"unitConversion\" table."}',
  unit_conversion_id,
  from_unit
) :: jsonb;

END IF;

result := jsonb_build_object(
  'error',
  result ->> 'error',
  'result',
  jsonb_build_object(
    'custom',
    custom_conversions,
    'others',
    standard_conversions
  )
);

RETURN QUERY
SELECT
  1 as id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory."matchIngredientIngredient"(ingredients jsonb, ingredientids integer []) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE ingredient_i record;

ingredient record;

result jsonb;

arr jsonb := '[]';

matched_ingredient jsonb;

BEGIN IF ingredientIds IS NOT NULL THEN FOR ingredient_i IN
SELECT
  name,
  id
FROM
  ingredient.ingredient
WHERE
  name IS NOT NULL
  AND id = ANY(ingredientIds) LOOP
SELECT
  *
FROM
  jsonb_array_elements(ingredients) AS found_ingredient
WHERE
  (found_ingredient ->> 'ingredientName') :: text = ingredient_i.name into matched_ingredient;

IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'ingredientId',
  ingredient_i.id
);

END IF;

END LOOP;

ELSE FOR ingredient_i IN
SELECT
  name,
  id
FROM
  ingredient.ingredient
WHERE
  name IS NOT NULL LOOP
SELECT
  *
FROM
  jsonb_array_elements(ingredients) AS found_ingredient
WHERE
  (found_ingredient ->> 'ingredientName') :: text = ingredient_i.name into matched_ingredient;

IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'ingredientId',
  ingredient_i.id
);

END IF;

END LOOP;

END IF;

result := jsonb_build_object('matchIngredientIngredient', arr);

RETURN QUERY
SELECT
  1 AS id,
  result AS data;

END;

$ $;

CREATE FUNCTION inventory."matchIngredientSachetItem"(ingredients jsonb, supplieriteminputs integer []) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE supplier_item record;

result jsonb;

arr jsonb := '[]';

matched_ingredient jsonb;

BEGIN IF supplierItemInputs IS NOT NULL THEN FOR supplier_item IN
SELECT
  "sachetItem".id sachet_id,
  "supplierItem".id,
  "supplierItem".name
FROM
  inventory."sachetItem"
  Inner JOIN inventory."bulkItem" ON "bulkItemId" = "bulkItem"."id"
  Inner JOIN inventory."supplierItem" ON "supplierItemId" = "supplierItem"."id"
WHERE
  "supplierItem".id = ANY (supplierItemInputs) LOOP
SELECT
  *
FROM
  jsonb_array_elements(ingredients) AS found_ingredient
WHERE
  (found_ingredient ->> 'ingredientName') = supplier_item.name INTO matched_ingredient;

IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'supplierItemId',
  supplier_item.id,
  'sachetItemId',
  supplier_item.sachet_id
);

END IF;

END LOOP;

ELSE FOR supplier_item IN
SELECT
  "sachetItem".id sachet_id,
  "supplierItem".id,
  "supplierItem".name
FROM
  inventory."sachetItem"
  Inner JOIN inventory."bulkItem" ON "bulkItemId" = "bulkItem"."id"
  Inner JOIN inventory."supplierItem" ON "supplierItemId" = "supplierItem"."id" LOOP
SELECT
  *
FROM
  jsonb_array_elements(ingredients) AS found_ingredient
WHERE
  (found_ingredient ->> 'ingredientName') = supplier_item.name INTO matched_ingredient;

IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'supplierItemId',
  supplier_item.id,
  'sachetItemId',
  supplier_item.sachet_id
);

END IF;

END LOOP;

END IF;

result := jsonb_build_object('ingredientSachetItemMatches', arr);

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory."matchIngredientSupplierItem"(ingredients jsonb, supplieriteminputs integer []) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE supplier_item record;

ingredient record;

result jsonb;

arr jsonb := '[]';

matched_ingredient jsonb;

BEGIN IF supplierItemInputs IS NOT NULL THEN FOR supplier_item IN
SELECT
  "supplierItem".id,
  "supplierItem"."name"
FROM
  inventory."supplierItem"
WHERE
  "supplierItem".id = ANY (supplierItemInputs) LOOP
SELECT
  *
FROM
  jsonb_array_elements(ingredients) AS found_ingredient
WHERE
  (found_ingredient ->> 'ingredientName') = supplier_item.name INTO matched_ingredient;

IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'supplierItemId',
  supplier_item.id
);

END IF;

END LOOP;

ELSE FOR supplier_item IN
SELECT
  "supplierItem".id,
  "supplierItem"."name"
FROM
  inventory."supplierItem" LOOP
SELECT
  *
FROM
  jsonb_array_elements(ingredients) AS found_ingredient
WHERE
  (found_ingredient ->> 'ingredientName') = supplier_item.name INTO matched_ingredient;

IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'supplierItemId',
  supplier_item.id
);

END IF;

END LOOP;

END IF;

result := jsonb_build_object('ingredientSupplierItemMatches', arr);

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory."matchSachetIngredientSachet"(sachets jsonb, ingredientsachetids integer []) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE sachet_ingredient record;

sachet record;

result jsonb;

arr jsonb := '[]';

matched_sachet jsonb;

BEGIN IF ingredientSachetIds IS NOT NULL THEN FOR sachet_ingredient IN
SELECT
  "ingredientSachet".id,
  quantity,
  "processingName",
  name
FROM
  ingredient."ingredientSachet"
  JOIN ingredient."ingredientProcessing" ON "ingredientProcessingId" = "ingredientProcessing".id
  JOIN ingredient.ingredient ON "ingredientSachet"."ingredientId" = ingredient.id
WHERE
  "ingredientSachet"."quantity" IS NOT NULL
  AND "ingredientProcessing"."processingName" IS NOT NULL
  AND "ingredientSachet".id = ANY (ingredientSachetIds) LOOP
SELECT
  *
FROM
  jsonb_array_elements(sachets) AS found_sachet
WHERE
  (found_sachet ->> 'quantity') :: int = sachet_ingredient."quantity"
  AND (found_sachet ->> 'processingName') = sachet_ingredient."processingName"
  AND (found_sachet ->> 'ingredientName') = sachet_ingredient.name INTO matched_sachet;

IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'ingredientSachetId',
  sachet_ingredient.id,
  'isProcessingExactMatch',
  true
);

END IF;

END LOOP;

ELSE FOR sachet_ingredient IN
SELECT
  "ingredientSachet".id,
  quantity,
  "processingName",
  name
FROM
  ingredient."ingredientSachet"
  JOIN ingredient."ingredientProcessing" ON "ingredientProcessingId" = "ingredientProcessing".id
  JOIN ingredient.ingredient ON "ingredientSachet"."ingredientId" = ingredient.id
WHERE
  "ingredientSachet"."quantity" IS NOT NULL
  AND "ingredientProcessing"."processingName" IS NOT NULL LOOP
SELECT
  *
FROM
  jsonb_array_elements(sachets) AS found_sachet
WHERE
  (found_sachet ->> 'quantity') :: int = sachet_ingredient."quantity"
  AND (found_sachet ->> 'processingName') = sachet_ingredient."processingName"
  AND (found_sachet ->> 'ingredientName') = sachet_ingredient.name INTO matched_sachet;

IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'ingredientSachetId',
  sachet_ingredient.id,
  'isProcessingExactMatch',
  true
);

END IF;

END LOOP;

END IF;

result := jsonb_build_object('sachetIngredientSachetMatches', arr);

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory."matchSachetSachetItem"(sachets jsonb, sachetitemids integer []) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE supplier_item record;

sachet record;

result jsonb;

arr jsonb := '[]';

matched_sachet jsonb;

BEGIN IF sachetItemIds IS NOT NULL THEN FOR supplier_item IN
SELECT
  "supplierItem".id,
  "supplierItem"."name",
  "processingName",
  "bulkItem".id "processingId",
  "sachetItem"."unitSize",
  "sachetItem"."unit",
  "sachetItem".id sachet_item_id
FROM
  inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "supplierItem"."id" = "bulkItem"."supplierItemId"
  LEFT JOIN inventory."sachetItem" ON "sachetItem"."bulkItemId" = "bulkItem"."id"
WHERE
  "sachetItem"."unitSize" IS NOT NULL
  AND "sachetItem".id = ANY (sachetItemIds) LOOP
SELECT
  *
FROM
  jsonb_array_elements(sachets) AS found_sachet
WHERE
  (found_sachet ->> 'quantity') :: int = supplier_item."unitSize"
  AND (found_sachet ->> 'processingName') = supplier_item."processingName"
  AND (found_sachet ->> 'ingredientName') = supplier_item.name INTO matched_sachet;

IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'supplierItemId',
  supplier_item.id,
  'supplierItemUnit',
  supplier_item.unit,
  'matched_sachetId',
  supplier_item.sachet_item_id,
  'isProcessingExactMatch',
  true
);

END IF;

END LOOP;

ELSE FOR supplier_item IN
SELECT
  "supplierItem".id,
  "supplierItem"."name",
  "processingName",
  "bulkItem".id "processingId",
  "sachetItem"."unitSize",
  "sachetItem"."unit",
  "sachetItem"."id" sachet_item_id
FROM
  inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "supplierItem"."id" = "bulkItem"."supplierItemId"
  LEFT JOIN inventory."sachetItem" ON "sachetItem"."bulkItemId" = "bulkItem"."id"
WHERE
  "sachetItem"."unitSize" IS NOT NULL
  AND "processingName" IS NOT NULL LOOP
SELECT
  *
FROM
  jsonb_array_elements(sachets) AS found_sachet
WHERE
  (found_sachet ->> 'quantity') :: int = supplier_item."unitSize"
  AND (found_sachet ->> 'processingName') = supplier_item."processingName"
  AND (found_sachet ->> 'ingredientName') = supplier_item.name INTO matched_sachet;

IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'supplierItemId',
  supplier_item.id,
  'supplierItemUnit',
  supplier_item.unit,
  'matched_sachetId',
  supplier_item.sachet_item_id,
  'isProcessingExactMatch',
  true
);

END IF;

END LOOP;

END IF;

result := jsonb_build_object('sachetSachetItemMatches', arr);

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory."matchSachetSupplierItem"(sachets jsonb, supplieriteminputs integer []) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE supplier_item record;

sachet record;

result jsonb;

arr jsonb := '[]';

matched_sachet jsonb;

BEGIN IF supplierItemInputs IS NOT NULL THEN FOR supplier_item IN
SELECT
  "supplierItem".id,
  "supplierItem"."name",
  "supplierItem"."unitSize",
  "supplierItem".unit,
  "processingName"
FROM
  inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "bulkItemAsShippedId" = "bulkItem"."id"
WHERE
  "supplierItem".id = ANY (supplierItemInputs) LOOP
SELECT
  *
FROM
  jsonb_array_elements(sachets) AS found_sachet
WHERE
  (found_sachet ->> 'quantity') :: int = supplier_item."unitSize"
  AND (found_sachet ->> 'processingName') = supplier_item."processingName"
  AND (found_sachet ->> 'ingredientName') = supplier_item.name INTO matched_sachet;

IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'supplierItemId',
  supplier_item.id,
  'isProcessingExactMatch',
  true
);

END IF;

END LOOP;

ELSE FOR supplier_item IN
SELECT
  "supplierItem".id,
  "supplierItem"."name",
  "supplierItem"."unitSize",
  "supplierItem".unit,
  "processingName"
FROM
  inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "bulkItemAsShippedId" = "bulkItem"."id"
WHERE
  "processingName" IS NOT NULL LOOP
SELECT
  *
FROM
  jsonb_array_elements(sachets) AS found_sachet
WHERE
  (found_sachet ->> 'quantity') :: int = supplier_item."unitSize"
  AND (found_sachet ->> 'processingName') = supplier_item."processingName"
  AND (found_sachet ->> 'ingredientName') = supplier_item.name INTO matched_sachet;

IF matched_sachet IS NOT NULL THEN arr := arr || jsonb_build_object(
  'sachet',
  matched_sachet,
  'supplierItemId',
  supplier_item.id,
  'isProcessingExactMatch',
  true
);

END IF;

END LOOP;

END IF;

result := jsonb_build_object('sachetSupplierItemMatches', arr);

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory."set_current_timestamp_updatedAt"() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updatedAt" = NOW();

RETURN _new;

END;

$ $;

CREATE FUNCTION inventory.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE FUNCTION inventory."standardToCustomUnitConverter"(
  quantity numeric,
  unit text,
  bulkdensity numeric DEFAULT 1,
  unit_to_id numeric DEFAULT NULL :: numeric
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE result jsonb := '{"error": null, "result": null}' :: jsonb;

custom_rule record;

converted_standard jsonb;

BEGIN -- unit_to_id is the id of a custom rule in master."unitConversion"
SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  id = unit_to_id into custom_rule;

IF custom_rule IS NOT NULL THEN
SELECT
  data
FROM
  inventory."unitVariationFunc"(
    quantity,
    unit,
    (-1) :: numeric,
    custom_rule.output_unit,
    -1
  ) into converted_standard;

result := jsonb_build_object(
  'error',
  'null' :: jsonb,
  'result',
  jsonb_build_object(
    'fromUnitName',
    unit,
    'toUnitName',
    custom_rule.input_unit,
    'value',
    quantity,
    'equivalentValue',
    (
      converted_standard -> 'result' -> 'standard' -> custom_rule.output_unit ->> 'equivalentValue'
    ) :: numeric / custom_rule.conversion_factor
  )
);

ELSE -- costruct an error msg
result := format(
  '{"error": "no custom unit is defined with the id: %s, create a conversion rule in the master.\"unitConversion\" table."}',
  unit_to_id
) :: jsonb;

END IF;

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory.standard_to_all_converter(
  quantity numeric,
  from_unit text,
  from_bulk_density numeric,
  tablename text,
  entity_id integer,
  all_mode text DEFAULT 'all' :: text
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ _ $ DECLARE definitions jsonb := $ $ { "kg": { "name": { "abbr" :"kg",
"singular" :"Kilogram",
"plural" :"Kilograms" },
"base" :"g",
"factor" :1000 },
"g": { "name": { "abbr" :"g",
"singular" :"Gram",
"plural" :"Grams" },
"base" :"g",
"factor" :1 },
"mg": { "name": { "abbr" :"mg",
"singular" :"Miligram",
"plural" :"MiliGrams" },
"base" :"g",
"factor" :0.001 },
"oz": { "name": { "abbr" :"oz",
"singular" :"Ounce",
"plural" :"Ounces" },
"base" :"g",
"factor" :28.3495 },
"l": { "name": { "abbr" :"l",
"singular" :"Litre",
"plural" :"Litres" },
"base" :"ml",
"factor" :1000,
"bulkDensity" :1 },
"ml": { "name": { "abbr" :"ml",
"singular" :"Millilitre",
"plural" :"Millilitres" },
"base" :"ml",
"factor" :1,
"bulkDensity" :1 } } $ $;

unit_key record;

custom_unit_key record;

from_definition jsonb;

local_result jsonb;

result_standard jsonb := '{}' :: jsonb;

result_custom jsonb := '{}' :: jsonb;

result jsonb := '{"error": null, "result": null}' :: jsonb;

converted_value numeric;

BEGIN IF all_mode = 'standard'
OR all_mode = 'all' THEN from_definition := definitions -> from_unit;

FOR unit_key IN
SELECT
  key,
  value
FROM
  jsonb_each(definitions) LOOP -- unit_key is definition from definitions.
  IF unit_key.value -> 'bulkDensity' THEN -- to is volume
  IF from_definition -> 'bulkDensity' THEN -- from is volume too
  converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric / (unit_key.value ->> 'bulkDensity') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

ELSE -- to is mass
IF from_definition -> 'bulkDensity' THEN -- from is volume 
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric * (from_unit_bulk_density) :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass too
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

END IF;

result_standard := result_standard || jsonb_build_object(unit_key.key, local_result);

END LOOP;

ELSEIF all_mode = 'custom'
OR all_mode = 'all' THEN FOR custom_unit_key IN EXECUTE format(
  $ $
  SELECT
    "inputUnitName" input_unit,
    "outputUnitName" output_unit,
    "conversionFactor" conversion_factor,
    "unitConversionId" unit_conversion_id
  FROM
    % I
    INNER JOIN master."unitConversion" ON "unitConversionId" = "unitConversion".id
  WHERE
    "entityId" = (% s) :: integer;

$ $,
tablename,
entity_id
) LOOP
SELECT
  data
FROM
  inventory.standard_to_custom_unit_converter(
    quantity,
    from_unit,
    from_bulk_density,
    custom_unit_key.input_unit,
    (-1) :: numeric,
    custom_unit_key.unit_conversion_id
  ) INTO local_result;

result_custom := result_custom || jsonb_build_object(custom_unit_key.input_unit, local_result);

END LOOP;

END IF;

result := jsonb_build_object(
  'result',
  jsonb_build_object(
    'standard',
    result_standard,
    'custom',
    result_custom
  ),
  'error',
  'null' :: jsonb
);

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ _ $;

CREATE FUNCTION inventory.standard_to_all_converter(
  quantity numeric,
  from_unit text,
  from_bulk_density numeric,
  schemaname text DEFAULT '' :: text,
  tablename text DEFAULT '' :: text,
  entity_id integer DEFAULT '-1' :: integer,
  all_mode text DEFAULT 'all' :: text
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ _ $ DECLARE definitions jsonb := $ $ { "kg": { "name": { "abbr" :"kg",
"singular" :"Kilogram",
"plural" :"Kilograms" },
"base" :"g",
"factor" :1000 },
"g": { "name": { "abbr" :"g",
"singular" :"Gram",
"plural" :"Grams" },
"base" :"g",
"factor" :1 },
"mg": { "name": { "abbr" :"mg",
"singular" :"Miligram",
"plural" :"MiliGrams" },
"base" :"g",
"factor" :0.001 },
"oz": { "name": { "abbr" :"oz",
"singular" :"Ounce",
"plural" :"Ounces" },
"base" :"g",
"factor" :28.3495 },
"l": { "name": { "abbr" :"l",
"singular" :"Litre",
"plural" :"Litres" },
"base" :"ml",
"factor" :1000,
"bulkDensity" :1 },
"ml": { "name": { "abbr" :"ml",
"singular" :"Millilitre",
"plural" :"Millilitres" },
"base" :"ml",
"factor" :1,
"bulkDensity" :1 } } $ $;

unit_key record;

custom_unit_key record;

from_definition jsonb;

local_result jsonb;

result_standard jsonb := '{}' :: jsonb;

result_custom jsonb := '{}' :: jsonb;

result jsonb := '{"error": null, "result": null}' :: jsonb;

converted_value numeric;

BEGIN IF all_mode = 'standard'
OR all_mode = 'all' THEN from_definition := definitions -> from_unit;

FOR unit_key IN
SELECT
  key,
  value
FROM
  jsonb_each(definitions) LOOP -- unit_key is definition from definitions.
  IF unit_key.value -> 'bulkDensity' THEN -- to is volume
  IF from_definition -> 'bulkDensity' THEN -- from is volume too
  converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric / (unit_key.value ->> 'bulkDensity') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

ELSE -- to is mass
IF from_definition -> 'bulkDensity' THEN -- from is volume 
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric * (from_unit_bulk_density) :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass too
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

END IF;

result_standard := result_standard || jsonb_build_object(unit_key.key, local_result);

END LOOP;

END IF;

IF all_mode = 'custom'
OR all_mode = 'all' THEN FOR custom_unit_key IN EXECUTE format(
  $ $
  SELECT
    "inputUnitName" input_unit,
    "outputUnitName" output_unit,
    "conversionFactor" conversion_factor,
    "unitConversionId" unit_conversion_id
  FROM
    % I.% I
    INNER JOIN master."unitConversion" ON "unitConversionId" = "unitConversion".id
  WHERE
    "entityId" = (% s) :: integer;

$ $,
schemaname,
tablename,
entity_id
) LOOP
SELECT
  data
FROM
  inventory.standard_to_custom_unit_converter(
    quantity,
    from_unit,
    from_bulk_density,
    custom_unit_key.input_unit,
    (1) :: numeric,
    custom_unit_key.unit_conversion_id
  ) INTO local_result;

result_custom := result_custom || jsonb_build_object(custom_unit_key.input_unit, local_result);

END LOOP;

END IF;

result := jsonb_build_object(
  'result',
  jsonb_build_object(
    'standard',
    result_standard,
    'custom',
    result_custom
  ),
  'error',
  'null' :: jsonb
);

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ _ $;

CREATE FUNCTION inventory.standard_to_custom_unit_converter(
  quantity numeric,
  from_unit text,
  from_bulk_density numeric,
  to_unit text,
  to_unit_bulk_density numeric,
  unit_conversion_id integer
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ $ DECLARE result jsonb := '{"error": null, "result": null}' :: jsonb;

custom_rule record;

converted_standard jsonb;

BEGIN -- unit_to_id is the id of a custom rule in master."unitConversion"
SELECT
  "inputUnitName" input_unit,
  "outputUnitName" output_unit,
  "conversionFactor" conversion_factor
FROM
  master."unitConversion"
WHERE
  id = unit_conversion_id into custom_rule;

IF custom_rule IS NOT NULL THEN
SELECT
  data
FROM
  inventory.standard_to_standard_unit_converter(
    quantity,
    from_unit,
    from_bulk_density,
    custom_rule.output_unit,
    to_unit_bulk_density,
    '',
    -- schemaname
    '',
    -- tablename
    0 -- entity id
  ) into converted_standard;

result := jsonb_build_object(
  'error',
  'null' :: jsonb,
  'result',
  jsonb_build_object(
    'fromUnitName',
    from_unit,
    'toUnitName',
    custom_rule.input_unit,
    'value',
    quantity,
    'equivalentValue',
    (
      converted_standard -> 'result' -> 'standard' -> custom_rule.output_unit ->> 'equivalentValue'
    ) :: numeric / custom_rule.conversion_factor
  )
);

ELSE -- costruct an error msg
result := format(
  '{"error": "no custom unit is defined with the id: %s and name: %s, create a conversion rule in the master.\"unitConversion\" table."}',
  unit_conversion_id,
  to_unit
) :: jsonb;

END IF;

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ $;

CREATE FUNCTION inventory.standard_to_standard_unit_converter(
  quantity numeric,
  from_unit text,
  from_bulk_density numeric,
  to_unit text,
  to_unit_bulk_density numeric,
  schemaname text,
  tablename text,
  entity_id integer,
  all_mode text DEFAULT 'all' :: text
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ _ $ DECLARE definitions jsonb := $ $ { "kg": { "name": { "abbr" :"kg",
"singular" :"Kilogram",
"plural" :"Kilograms" },
"base" :"g",
"factor" :1000 },
"g": { "name": { "abbr" :"g",
"singular" :"Gram",
"plural" :"Grams" },
"base" :"g",
"factor" :1 },
"mg": { "name": { "abbr" :"mg",
"singular" :"Miligram",
"plural" :"MiliGrams" },
"base" :"g",
"factor" :0.001 },
"oz": { "name": { "abbr" :"oz",
"singular" :"Ounce",
"plural" :"Ounces" },
"base" :"g",
"factor" :28.3495 },
"l": { "name": { "abbr" :"l",
"singular" :"Litre",
"plural" :"Litres" },
"base" :"ml",
"factor" :1000,
"bulkDensity" :1 },
"ml": { "name": { "abbr" :"ml",
"singular" :"Millilitre",
"plural" :"Millilitres" },
"base" :"ml",
"factor" :1,
"bulkDensity" :1 } } $ $;

unit_key record;

from_definition jsonb;

to_definition jsonb;

local_result jsonb;

result_standard jsonb := '{}' :: jsonb;

result jsonb := '{"error": null, "result": null}' :: jsonb;

converted_value numeric;

BEGIN -- 1. get the from definition of this unit;
from_definition := definitions -> from_unit;

-- gql forces the value of uni_to, passing '' should work.
IF to_unit = ''
OR to_unit IS NULL THEN -- to_unit is '', convert to all (standard to custom)
SELECT
  data
from
  inventory.standard_to_all_converter(
    quantity,
    from_unit,
    from_bulk_density,
    schemaname,
    tablename,
    entity_id,
    all_mode
  ) INTO result;

ELSE to_definition := definitions -> to_unit;

IF to_definition -> 'bulkDensity' THEN -- to is volume
IF from_definition -> 'bulkDensity' THEN -- from is volume too
-- ignore bulkDensity as they should be same in volume to volume of same entity.
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric / (to_unit_bulk_density) :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

ELSE -- to is mass
IF from_definition -> 'bulkDensity' THEN -- from is volume 
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric * (from_bulk_density) :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass too
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  from_unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

END IF;

result_standard := result_standard || jsonb_build_object(to_definition -> 'name' ->> 'abbr', local_result);

result := jsonb_build_object(
  'result',
  jsonb_build_object('standard', result_standard),
  'error',
  'null' :: jsonb
);

END IF;

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ _ $;

CREATE FUNCTION inventory."unitVariationFunc"(
  quantity numeric,
  unit text DEFAULT NULL :: text,
  bulkdensity numeric DEFAULT 1,
  unitto text DEFAULT NULL :: text,
  unit_id integer DEFAULT NULL :: integer
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ _ $ DECLARE definitions jsonb := $ $ { "kg": { "name": { "abbr" :"kg",
"singular" :"Kilogram",
"plural" :"Kilograms" },
"base" :"g",
"factor" :1000 },
"g": { "name": { "abbr" :"g",
"singular" :"Gram",
"plural" :"Grams" },
"base" :"g",
"factor" :1 },
"mg": { "name": { "abbr" :"mg",
"singular" :"Miligram",
"plural" :"MiliGrams" },
"base" :"g",
"factor" :0.001 },
"oz": { "name": { "abbr" :"oz",
"singular" :"Ounce",
"plural" :"Ounces" },
"base" :"g",
"factor" :28.3495 },
"l": { "name": { "abbr" :"l",
"singular" :"Litre",
"plural" :"Litres" },
"base" :"ml",
"factor" :1000,
"bulkDensity" :1 },
"ml": { "name": { "abbr" :"ml",
"singular" :"Millilitre",
"plural" :"Millilitres" },
"base" :"ml",
"factor" :1,
"bulkDensity" :1 } } $ $;

known_units text [] := '{kg, g, mg, oz, l, ml}';

unit_key record;

from_definition jsonb;

to_definition jsonb;

local_result jsonb;

result_standard jsonb := '{}' :: jsonb;

result jsonb := '{"error": null, "result": null}' :: jsonb;

converted_value numeric;

BEGIN IF unit = ANY(known_units) THEN -- 1. get the from definition of this unit;
from_definition := definitions -> unit;

-- gql forces the value of unitTo, passing '' should work.
IF unitTo IS NULL
OR unitTo = '' THEN FOR unit_key IN
SELECT
  key,
  value
FROM
  jsonb_each(definitions) LOOP -- unit_key is definition from definitions.
  IF unit_key.value -> 'bulkDensity' THEN -- to is volume
  IF from_definition -> 'bulkDensity' THEN -- from is volume too
  converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass
converted_value := quantity * (unit_key.value ->> 'bulkDensity') :: numeric * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

ELSE -- to is mass
IF from_definition -> 'bulkDensity' THEN -- from is volume 
converted_value := quantity * (from_definition ->> 'bulkDensity') :: numeric * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass too
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

END IF;

result_standard := result_standard || jsonb_build_object(unit_key.key, local_result);

END LOOP;

ELSE -- unitTo is not null
to_definition := definitions -> unitTo;

IF to_definition -> 'bulkDensity' THEN -- to is volume
IF from_definition -> 'bulkDensity' THEN -- from is volume too
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass
converted_value := quantity * (to_definition ->> 'bulkDensity') :: numeric * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

ELSE -- to is mass
IF from_definition -> 'bulkDensity' THEN -- from is volume 
converted_value := quantity * (from_definition ->> 'bulkDensity') :: numeric * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass too
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

END IF;

result_standard := result_standard || jsonb_build_object(to_definition -> 'name' ->> 'abbr', local_result);

END IF;

result := jsonb_build_object(
  'result',
  jsonb_build_object('standard', result_standard),
  'error',
  'null' :: jsonb
);

ELSE -- @param unit is not in standard_definitions
IF unit_id IS NULL THEN result := jsonb_build_object('error', 'unit_id must not be null');

ELSE -- check if customConversion is possible with @param unit
-- inventory."customUnitVariationFunc" also does error handling for us :)
-- @param unit_id should not be null here
-- @param unitTo is a standard unit
SELECT
  data
from
  inventory."customUnitVariationFunc"(quantity, unit_id, unitTo) into result;

END IF;

END IF;

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ _ $;

CREATE FUNCTION inventory."unitVariationFunc"(
  tablename text,
  quantity numeric,
  unit text,
  bulkdensity numeric DEFAULT 1,
  unitto text DEFAULT NULL :: text
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ _ $ DECLARE definitions jsonb := $ $ { "kg": { "name": { "abbr" :"kg",
"singular" :"Kilogram",
"plural" :"Kilograms" },
"base" :"g",
"factor" :1000 },
"g": { "name": { "abbr" :"g",
"singular" :"Gram",
"plural" :"Grams" },
"base" :"g",
"factor" :1 },
"mg": { "name": { "abbr" :"mg",
"singular" :"Miligram",
"plural" :"MiliGrams" },
"base" :"g",
"factor" :0.001 },
"oz": { "name": { "abbr" :"oz",
"singular" :"Ounce",
"plural" :"Ounces" },
"base" :"g",
"factor" :28.3495 },
"l": { "name": { "abbr" :"l",
"singular" :"Litre",
"plural" :"Litres" },
"base" :"ml",
"factor" :1000,
"bulkDensity" :1 },
"ml": { "name": { "abbr" :"ml",
"singular" :"Millilitre",
"plural" :"Millilitres" },
"base" :"ml",
"factor" :1,
"bulkDensity" :1 } } $ $;

known_units text [] := '{kg, g, mg, oz, l, ml}';

unit_key record;

from_definition jsonb;

to_definition jsonb;

local_result jsonb;

result_standard jsonb := '{}' :: jsonb;

result jsonb := '{"error": null, "result": null}' :: jsonb;

converted_value numeric;

BEGIN IF unit = ANY(known_units) THEN -- 1. get the from definition of this unit;
from_definition := definitions -> unit;

-- gql forces the value of unitTo, passing "" should work.
IF unitTo IS NULL
OR unitTo = '' THEN FOR unit_key IN
SELECT
  key,
  value
FROM
  jsonb_each(definitions) LOOP -- unit_key is definition from definitions.
  IF unit_key.value -> 'bulkDensity' THEN -- to is volume
  IF from_definition -> 'bulkDensity' THEN -- from is volume too
  converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass
converted_value := quantity * (unit_key.value ->> 'bulkDensity') :: numeric * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

ELSE -- to is mass
IF from_definition -> 'bulkDensity' THEN -- from is volume 
converted_value := quantity * (from_definition ->> 'bulkDensity') :: numeric * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass too
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (unit_key.value ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  unit_key.key,
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

END IF;

result_standard := result_standard || jsonb_build_object(unit_key.key, local_result);

END LOOP;

ELSE -- unitTo is not null
to_definition := definitions -> unitTo;

IF to_definition -> 'bulkDensity' THEN -- to is volume
IF from_definition -> 'bulkDensity' THEN -- from is volume too
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass
converted_value := quantity * (to_definition ->> 'bulkDensity') :: numeric * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

ELSE -- to is mass
IF from_definition -> 'bulkDensity' THEN -- from is volume 
converted_value := quantity * (from_definition ->> 'bulkDensity') :: numeric * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

ELSE -- from is mass too
converted_value := quantity * (from_definition ->> 'factor') :: numeric / (to_definition ->> 'factor') :: numeric;

local_result := jsonb_build_object(
  'fromUnitName',
  unit,
  'toUnitName',
  to_definition -> 'name' ->> 'abbr',
  'value',
  quantity,
  'equivalentValue',
  converted_value
);

END IF;

END IF;

result_standard := result_standard || jsonb_build_object(to_definition -> 'name' ->> 'abbr', local_result);

END IF;

-- TODO: is is_unit_to_custom == true -> handle standard to custom (probably another sql func)
result := jsonb_build_object(
  'result',
  jsonb_build_object('standard', result_standard),
  'error',
  'null' :: jsonb
);

ELSE -- @param unit is not in standard_definitions
-- check if customConversion is possible with @param unit
-- inventory."customUnitVariationFunc" also does error handling for us :)
SELECT
  data
from
  inventory."customUnitVariationFunc"(quantity, unit, unitTo) into result;

END IF;

RETURN QUERY
SELECT
  1 AS id,
  result as data;

END;

$ _ $;

CREATE TABLE inventory."supplierItem" (
  id integer DEFAULT public.defaultid(
    'inventory' :: text,
    'supplierItem' :: text,
    'id' :: text
  ) NOT NULL,
  name text,
  "unitSize" integer,
  prices jsonb,
  "supplierId" integer,
  unit text,
  "leadTime" jsonb,
  certificates jsonb,
  "bulkItemAsShippedId" integer,
  sku text,
  "importId" integer,
  "isArchived" boolean DEFAULT false NOT NULL,
  "unitConversionId" integer,
  "sachetItemAsShippedId" integer
);

CREATE FUNCTION inventory.unit_conversions_supplier_item(
  item inventory."supplierItem",
  from_unit text,
  from_unit_bulk_density numeric,
  quantity numeric,
  to_unit text,
  to_unit_bulk_density numeric
) RETURNS SETOF crm."customerData" LANGUAGE plpgsql STABLE AS $ _ $ DECLARE local_quantity numeric;

local_from_unit text;

local_from_unit_bulk_density numeric;

local_to_unit_bulk_density numeric;

known_units text [] := '{kg, g, mg, oz, l, ml}';

result jsonb;

custom_to_unit_conversion_id integer;

custom_from_unit_conversion_id integer;

BEGIN
/* setup */
-- resolve quantity
IF quantity IS NULL
OR quantity = -1 THEN local_quantity := item."unitSize" :: numeric;

ELSE local_quantity := quantity;

END IF;

-- resolve from_unit
IF from_unit IS NULL
OR from_unit = '' THEN local_from_unit := item.unit;

ELSE local_from_unit := from_unit;

END IF;

-- resolve from_unit_bulk_density
IF from_unit_bulk_density IS NULL
OR from_unit_bulk_density = -1 THEN local_from_unit_bulk_density := item."bulkDensity";

ELSE local_from_unit_bulk_density := from_unit_bulk_density;

END IF;

-- resolve to_unit_bulk_density
IF to_unit_bulk_density IS NULL
OR to_unit_bulk_density = -1 THEN local_to_unit_bulk_density := item."bulkDensity";

ELSE local_to_unit_bulk_density := to_unit_bulk_density;

END IF;

IF to_unit <> ALL(known_units)
AND to_unit != '' THEN EXECUTE format(
  $ $
  SELECT
    "unitConversionId" unit_conversion_id
  FROM
    % I.% I
    INNER JOIN master."unitConversion" ON "unitConversionId" = "unitConversion".id
  WHERE
    "entityId" = (% s) :: integer
    AND "inputUnitName" = '%s';

$ $,
'inventory',
-- schema name
'supplierItem_unitConversion',
-- tablename
item.id,
to_unit
) INTO custom_to_unit_conversion_id;

END IF;

IF local_from_unit <> ALL(known_units) THEN EXECUTE format(
  $ $
  SELECT
    "unitConversionId" unit_conversion_id
  FROM
    % I.% I
    INNER JOIN master."unitConversion" ON "unitConversionId" = "unitConversion".id
  WHERE
    "entityId" = (% s) :: integer
    AND "inputUnitName" = '%s';

$ $,
'inventory',
-- schema name
'supplierItem_unitConversion',
-- tablename
item.id,
local_from_unit
) INTO custom_from_unit_conversion_id;

END IF;

/* end setup */
IF local_from_unit = ANY(known_units) THEN -- local_from_unit is standard
IF to_unit = ANY(known_units)
OR to_unit = ''
OR to_unit IS NULL THEN -- to_unit is also standard
SELECT
  data
FROM
  inventory.standard_to_standard_unit_converter(
    local_quantity,
    local_from_unit,
    local_from_unit_bulk_density,
    to_unit,
    local_to_unit_bulk_density,
    'inventory',
    -- schema name
    'supplierItem_unitConversion',
    -- tablename
    item.id,
    'all'
  ) INTO result;

ELSE -- to_unit is custom and not ''
-- convert from standard to custom
SELECT
  data
FROM
  inventory.standard_to_custom_unit_converter(
    local_quantity,
    local_from_unit,
    local_from_unit_bulk_density,
    to_unit,
    local_to_unit_bulk_density,
    custom_to_unit_conversion_id
  ) INTO result;

END IF;

ELSE -- local_from_unit is custom
IF to_unit = ANY(known_units)
OR to_unit = ''
OR to_unit IS NULL THEN -- to_unit is standard
SELECT
  data
FROM
  inventory.custom_to_standard_unit_converter(
    local_quantity,
    local_from_unit,
    local_from_unit_bulk_density,
    to_unit,
    local_to_unit_bulk_density,
    custom_from_unit_conversion_id,
    'inventory',
    -- schema name
    'supplierItem_unitConversion',
    -- tablename
    item.id
  ) INTO result;

ELSE -- to_unit is also custom and not ''
SELECT
  data
FROM
  inventory.custom_to_custom_unit_converter(
    local_quantity,
    local_from_unit,
    local_from_unit_bulk_density,
    to_unit,
    local_to_unit_bulk_density,
    custom_from_unit_conversion_id,
    custom_to_unit_conversion_id
  ) INTO result;

END IF;

END IF;

RETURN QUERY
SELECT
  1 as id,
  result as data;

END;

$ _ $;

CREATE FUNCTION notifications.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE TABLE "onDemand".menu (
  id integer DEFAULT public.defaultid('onDemand' :: text, 'menu' :: text, 'id' :: text) NOT NULL,
  data jsonb
);

CREATE FUNCTION "onDemand"."getMenu"(params jsonb) RETURNS SETOF "onDemand".menu LANGUAGE plpgsql STABLE AS $ $ DECLARE colId int;

menu jsonb [] = '{}';

cleanMenu jsonb [] DEFAULT '{}';

r jsonb;

collection jsonb;

isValid jsonb;

category jsonb;

productCategory record;

product record;

oldObject jsonb;

newObject jsonb;

exists boolean := false;

index int;

i int;

arr int [];

BEGIN FOR colId IN
SELECT
  "collectionId"
FROM
  "onDemand"."brand_collection"
WHERE
  "brandId" = (params ->> 'brandId') :: int
  AND "isActive" = true LOOP
SELECT
  "onDemand"."isCollectionValid"(colId, params) INTO isValid;

-- RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', isValid) AS data;
IF (isValid -> 'status') :: boolean = true THEN FOR productCategory IN
SELECT
  *
FROM
  "onDemand"."collection_productCategory"
WHERE
  "collectionId" = colId
ORDER BY
  position DESC NULLS LAST LOOP category := jsonb_build_object(
    'name',
    productCategory."productCategoryName",
    'inventoryProducts',
    '{}',
    'simpleRecipeProducts',
    '{}',
    'customizableProducts',
    '{}',
    'comboProducts',
    '{}'
  );

FOR product IN
SELECT
  *
FROM
  "onDemand"."collection_productCategory_product"
WHERE
  "collection_productCategoryId" = productCategory.id
ORDER BY
  position DESC NULLS LAST LOOP IF product."simpleRecipeProductId" IS NOT NULL THEN category := category || jsonb_build_object(
    'simpleRecipeProducts',
    (
      REPLACE(
        REPLACE(category ->> 'simpleRecipeProducts', ']', '}'),
        '[',
        '{'
      )
    ) :: int [] || product."simpleRecipeProductId"
  );

ELSIF product."inventoryProductId" IS NOT NULL THEN category := category || jsonb_build_object(
  'inventoryProducts',
  (
    REPLACE(
      REPLACE(category ->> 'inventoryProducts', ']', '}'),
      '[',
      '{'
    )
  ) :: int [] || product."inventoryProductId"
);

ELSIF product."customizableProductId" IS NOT NULL THEN category := category || jsonb_build_object(
  'customizableProducts',
  (
    REPLACE(
      REPLACE(category ->> 'customizableProducts', ']', '}'),
      '[',
      '{'
    )
  ) :: int [] || product."customizableProductId"
);

ELSIF product."comboProductId" IS NOT NULL THEN category := category || jsonb_build_object(
  'comboProducts',
  (
    REPLACE(
      REPLACE(category ->> 'comboProducts', ']', '}'),
      '[',
      '{'
    )
  ) :: int [] || product."comboProductId"
);

ELSE CONTINUE;

END IF;

-- RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', product.id) AS data;
END LOOP;

-- RETURN QUERY SELECT category->>'name' AS name, category->'comboProducts' AS "comboProducts",  category->'customizableProducts' AS "customizableProducts", category->'simpleRecipeProducts' AS "simpleRecipeProducts", category->'inventoryProducts' AS "inventoryProducts";
menu := menu || category;

END LOOP;

ELSE CONTINUE;

END IF;

END LOOP;

-- RETURN;
FOREACH oldObject IN ARRAY(menu) LOOP exists := false;

i := NULL;

IF array_length(cleanMenu, 1) IS NOT NULL THEN FOR index IN 0..array_length(cleanMenu, 1) LOOP IF cleanMenu [index] ->> 'name' = oldObject ->> 'name' THEN exists := true;

i := index;

EXIT;

ELSE CONTINUE;

END IF;

END LOOP;

END IF;

IF exists = true THEN cleanMenu [i] := jsonb_build_object(
  'name',
  cleanMenu [i] ->> 'name',
  'simpleRecipeProducts',
  (
    REPLACE(
      REPLACE(
        cleanMenu [i] ->> 'simpleRecipeProducts',
        ']',
        '}'
      ),
      '[',
      '{'
    )
  ) :: int [] || (
    REPLACE(
      REPLACE(oldObject ->> 'simpleRecipeProducts', ']', '}'),
      '[',
      '{'
    )
  ) :: int [],
  'inventoryProducts',
  (
    REPLACE(
      REPLACE(cleanMenu [i] ->> 'inventoryProducts', ']', '}'),
      '[',
      '{'
    )
  ) :: int [] || (
    REPLACE(
      REPLACE(oldObject ->> 'inventoryProducts', ']', '}'),
      '[',
      '{'
    )
  ) :: int [],
  'customizableProducts',
  (
    REPLACE(
      REPLACE(
        cleanMenu [i] ->> 'customizableProducts',
        ']',
        '}'
      ),
      '[',
      '{'
    )
  ) :: int [] || (
    REPLACE(
      REPLACE(oldObject ->> 'customizableProducts', ']', '}'),
      '[',
      '{'
    )
  ) :: int [],
  'comboProducts',
  (
    REPLACE(
      REPLACE(cleanMenu [i] ->> 'comboProducts', ']', '}'),
      '[',
      '{'
    )
  ) :: int [] || (
    REPLACE(
      REPLACE(oldObject ->> 'comboProducts', ']', '}'),
      '[',
      '{'
    )
  ) :: int []
);

-- RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', cleanMenu[i]) AS data;
ELSE cleanMenu := cleanMenu || oldObject;

END IF;

END LOOP;

IF array_length(cleanMenu, 1) IS NOT NULL THEN FOR index IN 0..array_length(cleanMenu, 1) LOOP IF cleanMenu [index] ->> 'simpleRecipeProducts' = '{}' THEN cleanMenu [index] := cleanMenu [index] || jsonb_build_object(
  'simpleRecipeProducts',
  (cleanMenu [index] ->> 'simpleRecipeProducts') :: int []
);

END IF;

IF cleanMenu [index] ->> 'inventoryProducts' = '{}' THEN cleanMenu [index] := cleanMenu [index] || jsonb_build_object(
  'inventoryProducts',
  (cleanMenu [index] ->> 'inventoryProducts') :: int []
);

END IF;

IF cleanMenu [index] ->> 'customizableProducts' = '{}' THEN cleanMenu [index] := cleanMenu [index] || jsonb_build_object(
  'customizableProducts',
  (cleanMenu [index] ->> 'customizableProducts') :: int []
);

END IF;

IF cleanMenu [index] ->> 'comboProducts' = '{}' THEN cleanMenu [index] := cleanMenu [index] || jsonb_build_object(
  'comboProducts',
  (cleanMenu [index] ->> 'comboProducts') :: int []
);

END IF;

END LOOP;

END IF;

RETURN QUERY
SELECT
  1 AS id,
  jsonb_build_object('menu', cleanMenu) AS data;

END;

$ $;

CREATE FUNCTION "onDemand"."getMenuV2"(params jsonb) RETURNS SETOF "onDemand".menu LANGUAGE plpgsql STABLE AS $ $ DECLARE colId int;

idArr int [];

menu jsonb [] := '{}';

object jsonb;

isValid jsonb;

category jsonb;

productCategory record;

rec record;

cleanMenu jsonb [] := '{}';

-- without duplicates
cleanCategory jsonb;

-- without duplicates
categoriesIncluded text [];

productsIncluded int [];

updatedProducts int [];

productId int;

pos int := 0;

BEGIN -- generating menu data from collections
FOR colId IN
SELECT
  "collectionId"
FROM
  "onDemand"."brand_collection"
WHERE
  "brandId" = (params ->> 'brandId') :: int
  AND "isActive" = true LOOP
SELECT
  "onDemand"."isCollectionValid"(colId, params) INTO isValid;

IF (isValid -> 'status') :: boolean = true THEN FOR productCategory IN
SELECT
  *
FROM
  "onDemand"."collection_productCategory"
WHERE
  "collectionId" = colId
ORDER BY
  position DESC NULLS LAST LOOP idArr := '{}' :: int [];

FOR rec IN
SELECT
  *
FROM
  "onDemand"."collection_productCategory_product"
WHERE
  "collection_productCategoryId" = productCategory.id
ORDER BY
  position DESC NULLS LAST LOOP idArr := idArr || rec."productId";

END LOOP;

category := jsonb_build_object(
  'name',
  productCategory."productCategoryName",
  'products',
  idArr
);

menu := menu || category;

END LOOP;

ELSE CONTINUE;

END IF;

END LOOP;

-- merge duplicate categories and remove duplicate products
FOREACH category IN ARRAY(menu) LOOP pos := ARRAY_POSITION(categoriesIncluded, category ->> 'name');

IF pos >= 0 THEN updatedProducts := '{}' :: int [];

productsIncluded := '{}' :: int [];

FOR productId IN
SELECT
  *
FROM
  JSONB_ARRAY_ELEMENTS(cleanMenu [pos] -> 'products') LOOP updatedProducts := updatedProducts || productId;

productsIncluded := productsIncluded || productId;

-- wil remove same products under same category in different collections
END LOOP;

FOR productId IN
SELECT
  *
FROM
  JSONB_ARRAY_ELEMENTS(category -> 'products') LOOP IF ARRAY_POSITION(productsIncluded, productId) >= 0 THEN CONTINUE;

ELSE updatedProducts := updatedProducts || productId;

productsIncluded := productsIncluded || productId;

-- will remove same products under same category in same collection
END IF;

END LOOP;

cleanMenu [pos] := jsonb_build_object(
  'name',
  category ->> 'name',
  'products',
  updatedProducts
);

ELSE cleanMenu := cleanMenu || category;

categoriesIncluded := categoriesIncluded || (category ->> 'name') :: text;

END IF;

END LOOP;

RETURN QUERY
SELECT
  1 AS id,
  jsonb_build_object('menu', cleanMenu) AS data;

END;

$ $;

CREATE FUNCTION "onDemand"."getOnlineStoreProduct"(productid integer, producttype text) RETURNS SETOF "onDemand".menu LANGUAGE plpgsql STABLE AS $ $ DECLARE res jsonb;

BEGIN IF producttype = 'simpleRecipeProduct' THEN
SELECT
  products."getOnlineStoreSRPProduct"(productid) INTO res;

ELSIF producttype = 'inventoryProduct' THEN
SELECT
  products."getOnlineStoreIPProduct"(productid) INTO res;

ELSIF producttype = 'customizableProduct' THEN
SELECT
  products."getOnlineStoreCUSPProduct"(productid) INTO res;

ELSE
SELECT
  products."getOnlineStoreCOMPProduct"(productid) INTO res;

END IF;

RETURN QUERY
SELECT
  1 AS id,
  res AS data;

END;

$ $;

CREATE TABLE "onDemand"."collection_productCategory_product" (
  "collection_productCategoryId" integer NOT NULL,
  id integer DEFAULT public.defaultid(
    'onDemand' :: text,
    'collection_productCategory_product' :: text,
    'id' :: text
  ) NOT NULL,
  "position" numeric,
  "importHistoryId" integer,
  "productId" integer NOT NULL
);

CREATE FUNCTION "onDemand"."getProductDetails"(
  rec "onDemand"."collection_productCategory_product"
) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE product record;

productName text;

productType text;

productImage text;

BEGIN IF rec."simpleRecipeProductId" IS NOT NULL THEN
SELECT
  *
FROM
  products."simpleRecipeProduct"
WHERE
  id = rec."simpleRecipeProductId" INTO product;

productName := product.name;

productType := 'simpleRecipeProduct';

IF product.assets IS NOT NULL
AND JSONB_ARRAY_LENGTH(product.assets -> 'images') > 0 THEN productImage := product.assets -> 'images' #>>'{0}';
ELSE productImage := NULL;

END IF;

ELSIF rec."inventoryProductId" IS NOT NULL THEN
SELECT
  *
FROM
  products."inventoryProduct"
WHERE
  id = rec."inventoryProductId" INTO product;

productName := product.name;

productType := 'inventoryProduct';

IF product.assets IS NOT NULL
AND JSONB_ARRAY_LENGTH(product.assets -> 'images') > 0 THEN productImage := product.assets -> 'images' #>>'{0}';
ELSE productImage := NULL;

END IF;

ELSEIF rec."customizableProductId" IS NOT NULL THEN
SELECT
  *
FROM
  products."customizableProduct"
WHERE
  id = rec."customizableProductId" INTO product;

productName := product.name;

productType := 'customizableProduct';

IF product.assets IS NOT NULL
AND JSONB_ARRAY_LENGTH(product.assets -> 'images') > 0 THEN productImage := product.assets -> 'images' #>>'{0}';
ELSE productImage := NULL;

END IF;

ELSE
SELECT
  *
FROM
  products."comboProduct"
WHERE
  id = rec."comboProductId" INTO product;

productName := product.name;

productType := 'comboProduct';

IF product.assets IS NOT NULL
AND JSONB_ARRAY_LENGTH(product.assets -> 'images') > 0 THEN productImage := product.assets -> 'images' #>>'{0}';
ELSE productImage := NULL;

END IF;

END IF;

RETURN jsonb_build_object(
  'name',
  productName,
  'type',
  productType,
  'image',
  productImage
);

END $ $;

CREATE TABLE "onDemand"."storeData" (
  id integer DEFAULT public.defaultid(
    'onDemand' :: text,
    'storeData' :: text,
    'id' :: text
  ) NOT NULL,
  "brandId" integer,
  settings jsonb
);

CREATE FUNCTION "onDemand"."getStoreData"(requestdomain text) RETURNS SETOF "onDemand"."storeData" LANGUAGE plpgsql STABLE AS $ $ DECLARE brandId int;

settings jsonb;

BEGIN
SELECT
  id
FROM
  brands.brand
WHERE
  "domain" = requestDomain INTO brandId;

IF brandId IS NULL THEN
SELECT
  id
FROM
  brands.brand
WHERE
  "isDefault" = true INTO brandId;

END IF;

SELECT
  brands."getSettings"(brandId) INTO settings;

RETURN QUERY
SELECT
  1 AS id,
  brandId AS brandId,
  settings as settings;

END;

$ $;

CREATE FUNCTION "onDemand"."isCollectionValid"(collectionid integer, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ DECLARE res jsonb;

collection record;

isValid boolean := false;

BEGIN IF params ->> 'date' IS NOT NULL THEN
SELECT
  *
FROM
  "onDemand"."collection"
WHERE
  id = collectionId INTO collection;

IF collection."rrule" IS NOT NULL THEN
SELECT
  rules."rruleHasDateFunc"(
    collection."rrule" :: _rrule.rruleset,
    (params ->> 'date') :: timestamp
  ) INTO isValid;

ELSE isValid := true;

END IF;

END IF;

res := jsonb_build_object('status', isValid);

return res;

END;

$ $;

CREATE TABLE "onDemand"."modifierCategoryOption" (
  id integer DEFAULT public.defaultid(
    'onDemand' :: text,
    'modifierCategoryOption' :: text,
    'id' :: text
  ) NOT NULL,
  name text NOT NULL,
  "originalName" text NOT NULL,
  price numeric DEFAULT 0 NOT NULL,
  discount numeric DEFAULT 0 NOT NULL,
  quantity integer DEFAULT 1 NOT NULL,
  image text,
  "isActive" boolean DEFAULT true NOT NULL,
  "isVisible" boolean DEFAULT true NOT NULL,
  "operationConfigId" integer,
  "modifierCategoryId" integer NOT NULL,
  "sachetItemId" integer,
  "ingredientSachetId" integer,
  "simpleRecipeYieldId" integer,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE FUNCTION "onDemand"."modifierCategoryOptionCartItem"(option "onDemand"."modifierCategoryOption") RETURNS jsonb LANGUAGE plpgsql STABLE AS $ $ BEGIN -- counter := option.quantity;
-- IF option."sachetItemId" IS NOT NULL THEN 
--     WHILE counter >= 1 LOOP
--         items := items || jsonb_build_object('sachetItemId', option."sachetItemId", 'modifierOptionId', option.id);
--         counter := counter - 1;
--     END LOOP;
-- ELSEIF option."simpleRecipeYieldId" IS NOT NULL THEN
--     WHILE counter >= 1 LOOP
--         items := items || jsonb_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId", 'modifierOptionId', option.id);
--         counter := counter - 1;
--     END LOOP;
-- ELSEIF option."ingredientSachetId" IS NOT NULL THEN
--     WHILE counter >= 1 LOOP
--         items := items || jsonb_build_object('ingredientSachetId', option."ingredientSachetId", 'modifierOptionId', option.id);
--         counter := counter - 1;
--     END LOOP;
-- ELSE
--     items := items;
-- END IF;
RETURN jsonb_build_object(
  'data',
  jsonb_build_array(
    jsonb_build_object(
      'unitPrice',
      option.price,
      'modifierOptionId',
      option.id
    )
  )
);

END;

$ $;

CREATE FUNCTION "onDemand"."numberOfCategories"(colid integer) RETURNS integer LANGUAGE plpgsql STABLE AS $ $ DECLARE res int;

BEGIN
SELECT
  COUNT(*)
FROM
  "onDemand"."collection_productCategory"
WHERE
  "collectionId" = colId INTO res;

RETURN res;

END;

$ $;

CREATE FUNCTION "onDemand"."numberOfProducts"(colid integer) RETURNS integer LANGUAGE plpgsql STABLE AS $ $ DECLARE arr int [] := '{}';

res int;

rec record;

BEGIN FOR rec IN
SELECT
  id
FROM
  "onDemand"."collection_productCategory"
WHERE
  "collectionId" = colId LOOP arr := arr || rec.id;

END LOOP;

SELECT
  COUNT(*)
FROM
  "onDemand"."collection_productCategory_product"
WHERE
  "collection_productCategoryId" = ANY(arr) INTO res;

return res;

END;

$ $;

CREATE FUNCTION "onDemand".set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $ $ DECLARE _new record;

BEGIN _new := NEW;

_new."updated_at" = NOW();

RETURN _new;

END;

$ $;

CREATE TABLE "order".cart (
  id integer DEFAULT public.defaultid('order' :: text, 'cart' :: text, 'id' :: text) NOT NULL,
  "paidPrice" numeric DEFAULT 0 NOT NULL,
  "customerId" integer,
  "paymentStatus" text DEFAULT 'PENDING' :: text NOT NULL,
  status text DEFAULT 'CART_PENDING' :: text NOT NULL,
  "paymentMethodId" text,
  "transactionId" text,
  "stripeCustomerId" text,
  "fulfillmentInfo" jsonb,
  tip numeric DEFAULT 0 NOT NULL,
  address jsonb,
  "customerInfo" jsonb,
  source text DEFAULT 'a-la-carte' :: text NOT NULL,
  "subscriptionOccurenceId" integer,
  "walletAmountUsed" numeric DEFAULT 0 NOT NULL,
  "isTest" boolean DEFAULT false NOT NULL,
  "brandId" integer NOT NULL,
  "couponDiscount" numeric DEFAULT 0 NOT NULL,
  "loyaltyPointsUsed" integer DEFAULT 0 NOT NULL,
  "paymentId" uuid,
  "paymentUpdatedAt" timestamp with time zone,
  "paymentRequestInfo" jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  "customerKeycloakId" text,
  "orderId" integer,
  amount numeric DEFAULT 0,
  "transactionRemark" jsonb,
  "stripeInvoiceId" text,
  "stripeInvoiceDetails" jsonb,
  "statementDescriptor" text,
  "paymentRetryAttempt" integer DEFAULT 0 NOT NULL
);