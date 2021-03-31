
CREATE FUNCTION brands."getSettings"(brandid integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    settings jsonb = '{}';
    setting record;
    brandValue jsonb;
    res jsonb;
BEGIN
    FOR setting IN SELECT * FROM brands."storeSetting" LOOP
        SELECT value FROM brands."brand_storeSetting" WHERE "storeSettingId" = setting.id AND "brandId" = brandId INTO brandValue;
        settings := settings || jsonb_build_object(setting.identifier, COALESCE(brandValue, setting.value));
    END LOOP;
    res := jsonb_build_object('brand', jsonb_build_object(
        'logo', settings->'Brand Logo'->>'url',
        'name', settings->'Brand Name'->>'name',
        'navLinks', settings->'Nav Links',
        'contact', settings->'Contact',
        'policyAvailability', settings->'Policy Availability'
    ), 'visual', jsonb_build_object(
        'color', settings->'Primary Color'->>'color',
        'slides', settings->'Slides',
        'appTitle', settings->'App Title'->>'title',
        'favicon', settings->'Favicon'->>'url'
    ), 'availability', jsonb_build_object(
        'store', settings->'Store Availability',
        'pickup', settings->'Pickup Availability',
        'delivery', settings->'Delivery Availability',
        'referral', settings->'Referral Availability',
        'location', settings->'Location',
        'payments', settings->'Store Live'
    ), 'rewardsSettings', jsonb_build_object(
        'isLoyaltyPointsAvailable', (settings->'Loyalty Points Availability'->>'isAvailable')::boolean,
        'isWalletAvailable', (settings->'Wallet Availability'->>'isAvailable')::boolean,
        'isCouponsAvailable', (settings->'Coupons Availability'->>'isAvailable')::boolean,
        'loyaltyPointsUsage', settings->'Loyalty Points Usage'
    ), 'appSettings', jsonb_build_object(
        'scripts', settings->'Scripts'->>'value'
    ));
    RETURN res;
END;
$$;
CREATE FUNCTION content.set_current_timestamp_updated_at() RETURNS trigger
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
CREATE FUNCTION crm."createBrandCustomer"(keycloakid text, brandid integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO crm."brand_customer"("keycloakId", "brandId") VALUES(keycloakId, brandId);
END;
$$;
CREATE FUNCTION crm."createCustomer2"(keycloakid text, brandid integer, email text, clientid text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    customerId int;
BEGIN
    INSERT INTO crm.customer("keycloakId", "email", "sourceBrandId")
    VALUES(keycloakId, email, brandId)
    RETURNING id INTO customerId;
    RETURN customerId;
END;
$$;
CREATE FUNCTION crm."createCustomerWLR"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    params jsonb;
    rewardsParams jsonb;
    campaign record;
    campaignType text;
    keycloakId text;
    campaignValidity boolean := false;
    rewardValidity boolean;
    finalRewardValidity boolean := true;
    reward record;
    rewardIds int[] DEFAULT '{}';
    referral record;
BEGIN
    INSERT INTO crm.wallet("keycloakId", "brandId") VALUES (NEW."keycloakId", NEW."brandId");
    INSERT INTO crm."loyaltyPoint"("keycloakId", "brandId") VALUES (NEW."keycloakId", NEW."brandId");
    INSERT INTO crm."customerReferral"("keycloakId", "brandId") VALUES(NEW."keycloakId", NEW."brandId");
    --- check for signup campaigns
    params := jsonb_build_object('keycloakId', NEW."keycloakId", 'brandId', NEW."brandId");
    keycloakId := NEW."keycloakId";
    FOR campaign IN SELECT * FROM crm."campaign" WHERE id IN (SELECT "campaignId" FROM crm."brand_campaign" WHERE "brandId" = (params->'brandId')::int AND "isActive" = true) AND "type" = 'Sign Up' ORDER BY priority DESC, updated_at DESC LOOP
        SELECT * FROM crm."customerReferral" WHERE "keycloakId" = params->>'keycloakId' AND "brandId" = (params->>'brandId')::int INTO referral;
        IF referral."signupStatus" = 'COMPLETED' THEN
            EXIT;
        END IF;
        SELECT rules."isConditionValidFunc"(campaign."conditionId", params) INTO campaignValidity;
        IF campaignValidity = false THEN
            CONTINUE;
        END IF;
        IF campaign."isRewardMulti" = true THEN
            FOR reward IN SELECT * FROM crm.reward WHERE "campaignId" = campaign.id LOOP
                SELECT rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;
                IF rewardValidity = true THEN
                    rewardIds := rewardIds || reward.id;
                END IF;
                finalRewardValidity := finalRewardValidity AND rewardValidity;
            END LOOP;
        ELSE
            SELECT * FROM crm.reward WHERE "campaignId" = campaign.id ORDER BY priority DESC LIMIT 1 INTO reward;
            SELECT rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;
            IF rewardValidity = true THEN
                rewardIds := rewardIds || reward.id;
            END IF;
            finalRewardValidity := finalRewardValidity AND rewardValidity;
        END IF;
        IF finalRewardValidity = true AND array_length(rewardIds, 1) > 0 THEN
            rewardsParams := params || jsonb_build_object('campaignType', campaign."type", 'keycloakId', keycloakId);
            PERFORM crm."processRewardsForCustomer"(rewardIds, rewardsParams);
            IF campaign."type" = 'Sign Up' THEN
                UPDATE crm."customerReferral"
                SET "signupCampaignId" = campaign.id, "signupStatus" = 'COMPLETED'
                WHERE "keycloakId" = params->>'keycloakId' AND "brandId" = (params->>'brandId')::int;
            END IF;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$;
CREATE FUNCTION crm."deductLoyaltyPointsPostOrder"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    cart record;
    amount numeric;
    loyaltyPointId int;
    setting record;
    temp record;
    rate numeric;
BEGIN
    IF NEW."keycloakId" IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT * FROM "order"."cart" WHERE id = NEW."cartId" INTO cart;
    SELECT id FROM crm."loyaltyPoint" WHERE "keycloakId" = NEW."keycloakId" AND "brandId" = NEW."brandId" INTO loyaltyPointId; 
    IF cart."loyaltyPointsUsed" > 0 THEN
        SELECT crm."getLoyaltyPointsConversionRate"(NEW."brandId") INTO rate;
        amount := ROUND((cart."loyaltyPointsUsed" * rate), 2);
        INSERT INTO crm."loyaltyPointTransaction"("loyaltyPointId", "points", "orderCartId", "type", "amountRedeemed")
        VALUES (loyaltyPointId, cart."loyaltyPointsUsed", cart.id, 'DEBIT', amount);
    END IF;
    RETURN NULL;
END
$$;
CREATE FUNCTION crm."deductWalletAmountPostOrder"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    cart record;
    walletId int;
BEGIN
    IF NEW."keycloakId" IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT * FROM "order"."cart" WHERE id = NEW."cartId" INTO cart;
    SELECT id FROM crm."wallet" WHERE "keycloakId" = NEW."keycloakId" AND "brandId" = NEW."brandId" INTO walletId; 
    IF cart."walletAmountUsed" > 0 THEN
        INSERT INTO crm."walletTransaction"("walletId", "amount", "orderCartId", "type")
        VALUES (walletId, cart."walletAmountUsed", cart.id, 'DEBIT');
    END IF;
    RETURN NULL;
END
$$;

CREATE FUNCTION crm."getCustomer2"(keycloakid text, brandid integer, customeremail text, clientid text) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    customer record;
    brandCustomer record;
    newCustomerId int;
BEGIN
    SELECT * from crm.customer WHERE "keycloakId" = keycloakId INTO customer;
    IF customer IS NULL THEN
        SELECT crm."createCustomer2"(keycloakId, brandId, customerEmail, clientId) INTO newCustomerId;
    END IF;
    SELECT * FROM crm."brand_customer" WHERE "keycloakId" = keycloakId AND "brandId" = brandId INTO brandCustomer;
    IF brandCustomer is NULL THEN
        PERFORM crm."createBrandCustomer"(keycloakId, brandId);
    END IF;
    -- SELECT * FROM crm.customer WHERE "keycloakId" = keycloakId INTO customer;
    RETURN QUERY SELECT 1 AS id, jsonb_build_object('email', customeremail) AS data;
    -- RETURN jsonb_build_object('id', COALESCE(customer.id, newCustomerId), 'email', customeremail, 'isTest', false, 'keycloakId', keycloakid);
END;
$$;
CREATE FUNCTION crm."getLoyaltyPointsConversionRate"(brandid integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    setting record;
    temp record;
    obj jsonb;
BEGIN
    SELECT * FROM brands."storeSetting" WHERE "type" = 'rewards' and "identifier" = 'Loyalty Points Usage' INTO setting;
    SELECT * FROM brands."brand_storeSetting" WHERE "brandId" = brandid AND "storeSettingId" = setting.id INTO temp;
    -- IF temp IS NOT NULL THEN
    --     setting := temp;
    -- END IF;
    SELECT setting.value INTO obj;
    RETURN 0.01;
END
$$;
CREATE FUNCTION public.defaultid(schema text, tab text, col text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
 declare
 idVal integer;
 queryname text;
 existsquery text;
 sequencename text;
BEGIN
sequencename = ('"' || schema || '"'|| '.' || '"' || tab || '_' || col || '_seq' || '"')::text;
execute ('CREATE SEQUENCE IF NOT EXISTS' || sequencename || 'minvalue 1000 OWNED BY "' || schema || '"."' || tab || '"."' || col || '"' );
select (
'select nextval(''' 
|| sequencename || 
''')') into queryname;
select call(queryname)::integer into idVal;
select ('select exists(select "' || col || '" from "' || schema || '"."' || tab || '" where "' || col || '" = ' || idVal || ')') into existsquery;
WHILE exec(existsquery) = true LOOP
      select call(queryname) into idVal;
      select ('select exists(select "' || col || '" from "' || schema || '"."' || tab || '" where "' || col || '" = ' || idVal || ')') into existsquery;
END LOOP;
return idVal;
END
$$;

CREATE FUNCTION crm.iscampaignvalid(campaign crm.campaign) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res json;
    temp int;
BEGIN
    SELECT COUNT(*) FROM crm."reward" WHERE "campaignId" = campaign."id" LIMIT 1 into temp;
    IF campaign."conditionId" IS NULL AND temp < 1
        THEN res := json_build_object('status', false, 'error', 'Campaign Condition Or Reward not provided');
    ELSEIF campaign."conditionId" IS NULL
        THEN res := json_build_object('status', false, 'error', 'Campaign Condition not provided');
    ELSEIF temp < 1
        THEN res := json_build_object('status', false, 'error', 'Reward not provided');
    ELSEIF campaign."metaDetails"->'description' IS NULL OR coalesce(TRIM(campaign."metaDetails"->>'description'), '')= ''
        THEN res := json_build_object('status', false, 'error', 'Description not provided');
    ELSE
        res := json_build_object('status', true, 'error', '');
    END IF;
    RETURN res;
END
$$;

CREATE FUNCTION crm.iscouponvalid(coupon crm.coupon) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res json;
    temp int;
BEGIN
    SELECT COUNT(*) FROM crm."reward" WHERE "couponId" = coupon."id" into temp;
    IF coupon."visibleConditionId" IS NULL AND temp < 1
        THEN res := json_build_object('status', false, 'error', 'Coupon Condition Or Reward not provided');
    ELSEIF coupon."visibleConditionId" IS NULL
        THEN res := json_build_object('status', false, 'error', 'Coupon Condition not provided');
    ELSEIF temp < 1
        THEN res := json_build_object('status', false, 'error', 'Reward not provided');
    ELSEIF coupon."metaDetails"->'title' IS NULL OR coalesce(TRIM(coupon."metaDetails"->>'title'), '')= ''
        THEN res := json_build_object('status', false, 'error', 'Title not provided');
    ELSEIF coupon."metaDetails"->'description' IS NULL OR coalesce(TRIM(coupon."metaDetails"->>'description'), '')= ''
        THEN res := json_build_object('status', false, 'error', 'Description not provided');
    ELSE
        res := json_build_object('status', true, 'error', '');
    END IF;
    RETURN res;
END
$$;
CREATE FUNCTION crm."postOrderCouponRewards"() RETURNS trigger
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    rec record;
    reward record;
    rewardIds int[];
    params jsonb;
BEGIN
    IF NEW."keycloakId" IS NULL THEN
        RETURN NULL;
    END IF;
    params := jsonb_build_object('keycloakId', NEW."keycloakId", 'orderId', NEW.id, 'cartId', NEW."cartId", 'brandId', NEW."brandId", 'campaignType', 'Post Order');
    FOR rec IN SELECT * FROM "order"."cart_rewards" WHERE "cartId" = NEW."cartId" LOOP
        SELECT * FROM crm.reward WHERE id = rec."rewardId" INTO reward;
        IF reward."type" = 'Loyalty Point Credit' OR reward."type" = 'Wallet Amount Credit' THEN
            rewardIds := rewardIds || reward.id;
        END IF;
        rewardIds := rewardIds || rec."rewardId";
    END LOOP;
    IF array_length(rewardIds, 1) > 0 THEN
        PERFORM crm."processRewardsForCustomer"(rewardIds, params);
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION crm."processLoyaltyPointTransaction"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW."type" = 'CREDIT'
        THEN
        UPDATE crm."loyaltyPoint"
        SET points = points + NEW.points
        WHERE id = NEW."loyaltyPointId";
    ELSE
        UPDATE crm."loyaltyPoint"
        SET points = points - NEW.points
        WHERE id = NEW."loyaltyPointId";
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION crm."processRewardsForCustomer"(rewardids integer[], params jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    reward record;
    loyaltyPointId int;
    walletId int;
    pointsToBeCredited int;
    amountToBeCredited numeric;
    cartAmount numeric;
    returnedId int;
BEGIN
    FOR reward IN SELECT * FROM crm.reward WHERE id = ANY(rewardIds) LOOP
        IF reward."type" = 'Loyalty Point Credit' THEN 
            SELECT id FROM crm."loyaltyPoint" WHERE "keycloakId" = params->>'keycloakId' AND "brandId" = (params->>'brandId')::int INTO loyaltyPointId;
            IF loyaltyPointId IS NOT NULL THEN
                IF reward."rewardValue"->>'type' = 'absolute' THEN
                    SELECT (reward."rewardValue"->>'value')::int INTO pointsToBeCredited;
                ELSIF reward."rewardValue"->>'type' = 'conditional' AND params->>'campaignType' = 'Post Order' THEN
                    SELECT "amount" FROM "order"."cart" WHERE id = (params->'cartId')::int INTO cartAmount;
                    pointsToBeCredited := ROUND(cartAmount * ((reward."rewardValue"->'value'->'percentage')::numeric / 100));
                    IF pointsToBeCredited > (reward."rewardValue"->'value'->'max')::numeric THEN
                        pointsToBeCredited := (reward."rewardValue"->'value'->'max')::numeric;
                    END IF;
                ELSE
                    CONTINUE;
                END IF;
                INSERT INTO crm."loyaltyPointTransaction" ("loyaltyPointId", "points", "type")VALUES(loyaltyPointId, pointsToBeCredited, 'CREDIT') RETURNING id INTO returnedId;
                IF reward."couponId" IS NOT NULL THEN
                    INSERT INTO crm."rewardHistory"("rewardId", "couponId", "keycloakId", "orderCartId", "orderId", "loyaltyPointTransactionId", "loyaltyPoints", "brandId")
                    VALUES(reward.id, reward."couponId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, pointsToBeCredited, (params->>'brandId')::int);
                ELSE
                    INSERT INTO crm."rewardHistory"("rewardId", "campaignId", "keycloakId", "orderCartId", "orderId", "loyaltyPointTransactionId", "loyaltyPoints", "brandId")
                    VALUES(reward.id, reward."campaignId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, pointsToBeCredited, (params->>'brandId')::int);
                END IF;
            END IF;
        ELSIF reward."type" = 'Wallet Amount Credit' THEN
            SELECT id FROM crm."wallet" WHERE "keycloakId" = params->>'keycloakId' AND "brandId" = (params->>'brandId')::int INTO walletId;
            IF walletId IS NOT NULL THEN
                IF reward."rewardValue"->>'type' = 'absolute' THEN 
                    SELECT (reward."rewardValue"->>'value')::int INTO amountToBeCredited;
                ELSIF reward."rewardValue"->>'type' = 'conditional' AND params->>'campaignType' = 'Post Order' THEN
                    SELECT "amount" FROM "order"."cart" WHERE id = (params->'cartId')::int INTO cartAmount;
                    amountToBeCredited := ROUND(cartAmount * ((reward."rewardValue"->'value'->'percentage')::numeric / 100), 2);
                    IF amountToBeCredited > (reward."rewardValue"->'value'->'max')::numeric THEN
                        amountToBeCredited := (reward."rewardValue"->'value'->'max')::numeric;
                    END IF;
                ELSE
                    CONTINUE;
                END IF;
                INSERT INTO crm."walletTransaction" ("walletId", "amount", "type") VALUES(walletId, amountToBeCredited, 'CREDIT') RETURNING id INTO returnedId;
                IF reward."couponId" IS NOT NULL THEN
                    INSERT INTO crm."rewardHistory"("rewardId", "couponId", "keycloakId", "orderCartId", "orderId", "walletTransactionId", "walletAmount", "brandId")
                    VALUES(reward.id, reward."couponId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, amountToBeCredited, (params->>'brandId')::int);
                ELSE
                    INSERT INTO crm."rewardHistory"("rewardId", "campaignId", "keycloakId", "orderCartId", "orderId", "walletTransactionId", "walletAmount", "brandId")
                    VALUES(reward.id, reward."campaignId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, returnedId, amountToBeCredited, (params->>'brandId')::int);
                END IF;
            END IF;
        ELSIF reward."type" = 'Discount' THEN
            IF reward."couponId" IS NOT NULL THEN
                INSERT INTO crm."rewardHistory"("rewardId", "couponId", "keycloakId", "orderCartId", "orderId", "discount", "brandId")
                VALUES(reward.id, reward."couponId", params->>'keycloakId', (params->>'cartId')::int, (params->>'orderId')::int, (SELECT "couponDiscount" FROM "order"."cart" WHERE id = (params->>'cartId')::int), (params->>'brandId')::int);
            END IF;
        ELSE
            CONTINUE;
        END IF; 
    END LOOP;
END;
$$;
CREATE FUNCTION crm."processWalletTransaction"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW."type" = 'CREDIT'
        THEN
        UPDATE crm."wallet"
        SET amount = amount + NEW.amount
        WHERE id = NEW."walletId";
    ELSE
        UPDATE crm."wallet"
        SET amount = amount - NEW.amount
        WHERE id = NEW."walletId";
    END IF;
    RETURN NULL;
END;
$$;

CREATE FUNCTION crm."referralStatus"(fact crm.fact, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT crm."referralStatusFunc"(params) INTO result;
  RETURN result;
END;
$$;
CREATE FUNCTION crm."referralStatusFunc"(params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    referralStatus text ;
BEGIN
  SELECT "status" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referralStatus;
  RETURN json_build_object('value', referralStatus, 'valueType','text','argument','keycloakId');
END;
$$;
CREATE FUNCTION crm."rewardsTriggerFunction"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    params jsonb;
    rewardsParams jsonb;
    campaign record;
    condition record;
    campaignType text;
    keycloakId text;
    campaignValidity boolean := false;
    rewardValidity boolean;
    finalRewardValidity boolean := true;
    reward record;
    rewardIds int[] DEFAULT '{}';
    cartId int;
    referral record;
    postOrderRewardGiven boolean := false;
BEGIN
    IF NEW."keycloakId" IS NULL THEN
        RETURN NULL;
    END IF;
    IF TG_TABLE_NAME = 'customerReferral' THEN
        params := jsonb_build_object('keycloakId', NEW."keycloakId", 'brandId', NEW."brandId");
        SELECT "keycloakId" FROM crm."customerReferral" WHERE "referralCode" = NEW."referredByCode" INTO keycloakId;
    ELSIF TG_TABLE_NAME = 'order' THEN
        params := jsonb_build_object('keycloakId', NEW."keycloakId", 'orderId', NEW.id::int, 'cartId', NEW."cartId", 'brandId', NEW."brandId");
        keycloakId := NEW."keycloakId";
    ELSE 
        RETURN NULL;
    END IF;
    FOR campaign IN SELECT * FROM crm."campaign" WHERE id IN (SELECT "campaignId" FROM crm."brand_campaign" WHERE "brandId" = (params->'brandId')::int AND "isActive" = true) ORDER BY priority DESC, updated_at DESC LOOP
        SELECT * FROM crm."customerReferral" WHERE "keycloakId" = params->>'keycloakId' AND "brandId" = (params->>'brandId')::int INTO referral;
        IF campaign."type" = 'Sign Up' THEN
            CONTINUE;
        END IF;
        IF campaign."type" = 'Referral' AND (referral."referralStatus" = 'COMPLETED' OR referral."referredByCode" IS NULL) THEN
            CONTINUE;
        END IF;
        IF campaign."type" = 'Post Order' AND (params->>'cartId' IS NULL OR postOrderRewardGiven = true) THEN
            CONTINUE;
        END IF;
        SELECT rules."isConditionValidFunc"(campaign."conditionId", params) INTO campaignValidity;
        IF campaignValidity = false THEN
            CONTINUE;
        END IF;
        IF campaign."isRewardMulti" = true THEN
            FOR reward IN SELECT * FROM crm.reward WHERE "campaignId" = campaign.id LOOP
                SELECT rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;
                IF rewardValidity = true THEN
                    rewardIds := rewardIds || reward.id;
                END IF;
                -- 
                finalRewardValidity := finalRewardValidity AND rewardValidity;
            END LOOP;
        ELSE
            SELECT * FROM crm.reward WHERE "campaignId" = campaign.id ORDER BY priority DESC LIMIT 1 INTO reward;
            SELECT rules."isConditionValidFunc"(reward."conditionId", params) INTO rewardValidity;
            IF rewardValidity = true THEN
                rewardIds := rewardIds || reward.id;
            END IF;
            finalRewardValidity := finalRewardValidity AND rewardValidity;
        END IF;
        IF finalRewardValidity = true AND array_length(rewardIds, 1) > 0 THEN
            rewardsParams := params || jsonb_build_object('campaignType', campaign."type", 'keycloakId', keycloakId);
            PERFORM crm."processRewardsForCustomer"(rewardIds, rewardsParams);
            IF campaign."type" = 'Referral' THEN
                UPDATE crm."customerReferral"
                SET "referralCampaignId" = campaign.id, "referralStatus" = 'COMPLETED'
                WHERE "keycloakId" = params->>'keycloakId' AND "brandId" = (params->>'brandId')::int;
            ELSIF campaign."type" = 'Post Order' THEN
                postOrderRewardGiven := true;
            ELSE
                CONTINUE;
            END IF;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$;
CREATE FUNCTION crm."setLoyaltyPointsUsedInCart"(cartid integer, points integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "order"."cart"
    SET "loyaltyPointsUsed" = points
    WHERE id = cartid;
END
$$;

CREATE FUNCTION crm."setReferralCode"(params jsonb) RETURNS SETOF public.response
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    rec record;
    kId text;
    code text;
    success boolean := true;
    message text := 'Referral code applied!';
BEGIN
    SELECT "referredByCode" FROM  crm."customerReferral" WHERE "referralCode" = (params->>'referralCode')::text AND "brandId" = (params->>'brandId')::int INTO code;
    IF code IS NOT NULL THEN
        -- case when code is already applied
        success := false;
        message := 'Referral code already applied!';
    ELSE
        IF params->>'input' LIKE '%@%' THEN 
            SELECT "keycloakId" FROM crm.customer WHERE email = params->>'input' INTO kId;
            SELECT * FROM crm.brand_customer WHERE "keycloakId" = kId AND "brandId" = (params->>'brandId')::int INTO rec;
            IF rec IS NULL THEN
                success := false;
                message := 'Incorrect email!';
            END IF;
            IF kId IS NOT NULL THEN
                SELECT "referralCode" FROM crm."customerReferral" WHERE "keycloakId" = kId AND "brandId" = (params->>'brandId')::int INTO code;
                IF code IS NOT NULL AND code != params->>'referralCode' THEN
                    PERFORM "crm"."updateReferralCode"((params->>'referralCode')::text, code::text);
                ELSE
                    success := false;
                    message := 'Incorrect email!';
                END IF;
            ELSE
                success := false;
                message := 'Incorrect email!';
            END IF;
        ELSE
            SELECT "referralCode" FROM crm."customerReferral" WHERE "referralCode" = (params->>'input')::text AND "brandId" = (params->>'brandId')::int INTO code;
            IF code is NOT NULL AND code != params->>'referralCode' THEN
                PERFORM "crm"."updateReferralCode"((params->>'referralCode')::text, code::text);
            ELSE
                success := false;
                message := 'Incorrect referral code!';
            END IF;
        END IF;
    END IF;
    RETURN QUERY SELECT success AS success, message AS message;
END;
$$;
CREATE FUNCTION crm."setWalletAmountUsedInCart"(cartid integer, validamount numeric) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "order"."cart"
    SET "walletAmountUsed" = validAmount
    WHERE id = cartId;
END
$$;
CREATE FUNCTION crm.set_current_timestamp_updated_at() RETURNS trigger
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
CREATE FUNCTION crm."updateBrand_customer"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
   UPDATE "crm"."brand_customer"
SET "subscriptionTitleId" = (select "subscriptionTitleId" from "subscription"."subscription" where id = NEW."subscriptionId"),
"subscriptionServingId" = (select "subscriptionServingId" from "subscription"."subscription" where id = NEW."subscriptionId"),
"subscriptionItemCountId" = (select "subscriptionItemCountId" from "subscription"."subscription" where id = NEW."subscriptionId")
WHERE id = NEW.id;
    RETURN null;
END;
$$;
CREATE FUNCTION crm."updateReferralCode"(referralcode text, referredbycode text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE crm."customerReferral"
    SET "referredByCode" = referredByCode
    WHERE "referralCode" = referralCode;
END;
$$;
CREATE FUNCTION crm.updateissubscribertimestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    IF NEW."isSubscriber" = true and old."isSubscriber" = false THEN
    update "crm"."brand_customer" set "isSubscriberTimeStamp" = now();
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "deviceHub".set_current_timestamp_updated_at() RETURNS trigger
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

CREATE FUNCTION editor."HandlePriority4"(arg jsonb) RETURNS SETOF editor."priorityFuncTable"
    LANGUAGE plpgsql STABLE
    AS $$ 
DECLARE 
    currentdata jsonb;
    datalist jsonb :='[]';
    tablenameinput text;
    schemanameinput text;
    currentdataid int;
    currentdataposition numeric;
    columnToBeUpdated text;
BEGIN
    datalist := arg->>'data1';
    schemanameinput := arg->>'schemaname';
    tablenameinput := arg->>'tablename';
    columnToBeUpdated := COALESCE(arg->>'column', 'position');
IF arg IS NOT NULL THEN
    FOR currentdata IN SELECT * FROM jsonb_array_elements(datalist) LOOP
        currentdataid := currentdata->>'id';
        currentdataposition := currentdata->>columnToBeUpdated;
         PERFORM editor."updatePriorityFinal"(tablenameinput,schemanameinput, currentdataid, currentdataposition, columnToBeUpdated);
    END LOOP;
END IF;
RETURN QUERY
SELECT
  1 AS id;
END;
$$;
CREATE FUNCTION editor.set_current_timestamp_updated_at() RETURNS trigger
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
CREATE FUNCTION editor."updatePriorityFinal"(tablename text, schemaname text, id integer, pos numeric, col text) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE
    data record;
    querystring text := '';
BEGIN
  querystring := 'UPDATE '||'"'||schemaname||'"' || '.'||'"'||tablename||'"'||'set ' || col || ' ='|| pos ||'where "id" ='|| id ||' returning *';
    EXECUTE querystring into data ; 
  RETURN data;
END;
$$;

CREATE FUNCTION fulfilment."preOrderDeliveryValidity"(milerange fulfilment."mileRange", "time" time without time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    fromVal time;
    toVal time;
BEGIN
    SELECT "from" into fromVal FROM fulfilment."timeSlot" WHERE id = mileRange."timeSlotId";
    SELECT "to" into toVal FROM fulfilment."timeSlot" WHERE id = mileRange."timeSlotId";
    RETURN true;
END
$$;

CREATE FUNCTION fulfilment."preOrderPickupTimeFrom"(timeslot fulfilment."timeSlot") RETURNS time without time zone
    LANGUAGE plpgsql STABLE
    AS $$
  -- SELECT "from".timeslot AS fromtime, "pickupLeadTime".timeslot AS buffer, diff(fromtime, buffer) as "pickupFromTime"
  BEGIN
  return ("from".timeslot - "pickupLeadTime".timeslot);
  END
$$;
CREATE FUNCTION fulfilment."preOrderPickupValidity"(timeslot fulfilment."timeSlot", "time" time without time zone) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    -- IF JSONB_ARRAY_LENGTH(ordercart."cartInfo"->'products') = 0
    --     THEN RETURN json_build_object('status', false, 'error', 'No items in cart!');
    -- ELSIF ordercart."paymentMethodId" IS NULL OR ordercart."stripeCustomerId" IS NULL
    --     THEN RETURN json_build_object('status', false, 'error', 'No payment method selected!');
    -- ELSIF ordercart."address" IS NULL
    --     THEN RETURN json_build_object('status', false, 'error', 'No address selected!');
    -- ELSE
        RETURN true;
    -- END IF;
END
$$;
CREATE FUNCTION fulfilment.set_current_timestamp_updated_at() RETURNS trigger
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
CREATE FUNCTION ingredient."MOFCost"(mofid integer) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    mof record;
    bulkItemId int;
    supplierItemId int;
    supplierItem record;
    costs jsonb;
BEGIN
    SELECT * FROM ingredient."modeOfFulfillment" WHERE id = mofId into mof;
    IF mof."bulkItemId" IS NOT NULL
        THEN SELECT mof."bulkItemId" into bulkItemId;
    ELSE
        SELECT bulkItemId FROM inventory."sachetItem" WHERE id = mof."sachetItemId" into bulkItemId;
    END IF;
    SELECT "supplierItemId" FROM inventory."bulkItem" WHERE id = bulkItemId into supplierItemId;
    SELECT * FROM inventory."supplierItem" WHERE id = supplierItemId into supplierItem;
    IF supplierItem.prices IS NULL OR supplierItem.prices->0->'unitPrice'->>'value' = ''
        THEN RETURN 0;
    ELSE
        RETURN (supplierItem.prices->0->'unitPrice'->>'value')::numeric/supplierItem."unitSize";
    END IF;
END
$$;
CREATE FUNCTION ingredient."MOFNutritionalInfo"(mofid integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
    mof record;
    bulkItemId int;
BEGIN
    SELECT * FROM ingredient."modeOfFulfillment" WHERE id = mofId into mof;
    IF mof."bulkItemId" IS NOT NULL
        THEN SELECT "nutritionInfo" FROM inventory."bulkItem" WHERE id = mof."bulkItemId" into info;
        RETURN info;
    ELSE
        SELECT bulkItemId FROM inventory."sachetItem" WHERE id = mof."sachetItemId" into bulkItemId;
        SELECT "nutritionInfo" FROM inventory."bulkItem" WHERE id = bulkItemId into info;
        RETURN info;
    END IF;
END
$$;

CREATE FUNCTION ingredient.cost(sachet ingredient."ingredientSachet") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    cost numeric;
BEGIN
    SELECT ingredient."sachetCost"(sachet.id) into cost;
    RETURN cost;
END
$$;

CREATE FUNCTION ingredient."getMOFCost"(mof ingredient."modeOfFulfillment") RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    cost numeric;
BEGIN
    SELECT ingredient."MOFCost"(mof.id) into cost;
    RETURN cost;
END
$$;
CREATE FUNCTION ingredient."getMOFNutritionalInfo"(mof ingredient."modeOfFulfillment") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
BEGIN
    SELECT ingredient."MOFNutritionalInfo"(mof.id) into info;
    RETURN info;
END
$$;

CREATE FUNCTION ingredient.image_validity(ing ingredient.ingredient) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(ing.image IS NULL)
$$;
CREATE FUNCTION ingredient.imagevalidity(image ingredient.ingredient) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    SELECT NOT(image.image IS NULL)
$$;
CREATE FUNCTION ingredient.isingredientvalid(ingredient ingredient.ingredient) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    temp jsonb;
BEGIN
    SELECT * FROM ingredient."ingredientSachet" where "ingredientId" = ingredient.id LIMIT 1 into temp;
    IF temp IS NULL
        THEN return json_build_object('status', false, 'error', 'Not sachet present');
    ELSIF ingredient.category IS NULL
        THEN return json_build_object('status', false, 'error', 'Category not provided');
    ELSIF ingredient.image IS NULL OR LENGTH(ingredient.image) = 0
        THEN return json_build_object('status', true, 'error', 'Image not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION ingredient.ismodevalid(mode ingredient."modeOfFulfillment") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  temp json;
  isSachetValid boolean;
BEGIN
    SELECT ingredient.isSachetValid("ingredientSachet".*) 
        FROM ingredient."ingredientSachet"
        WHERE "ingredientSachet".id = mode."ingredientSachetId" into temp;
    SELECT temp->'status' into isSachetValid;
    IF NOT isSachetValid
        THEN return json_build_object('status', false, 'error', 'Sachet is not valid');
    ELSIF mode."stationId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Station is not provided');
    ELSIF mode."bulkItemId" IS NULL AND mode."sachetItemId" IS NULL
        THEN return json_build_object('status', false, 'error', 'Item is not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION ingredient.issachetvalid(sachet ingredient."ingredientSachet") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  temp json;
  isIngredientValid boolean;
BEGIN
    SELECT ingredient.isIngredientValid(ingredient.*) FROM ingredient.ingredient where ingredient.id = sachet."ingredientId" into temp;
    SELECT temp->'status' into isIngredientValid;
    IF NOT isIngredientValid
        THEN return json_build_object('status', false, 'error', 'Ingredient is not valid');
    -- ELSIF sachet."defaultNutritionalValues" IS NULL
    --     THEN return json_build_object('status', true, 'error', 'Default nutritional values not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;

CREATE FUNCTION ingredient.issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
BEGIN
    -- SELECT ingredient.isSachetValid("ingredientSachet".*) 
    --     FROM ingredient."ingredientSachet"
    --     WHERE "ingredientSachet".id = mode."ingredientSachetId" into temp;
    -- SELECT temp->'status' into isSachetValid;
    IF recipe.utensils IS NULL OR ARRAY_LENGTH(recipe.utensils) = 0
        THEN return json_build_object('status', false, 'error', 'Utensils not provided');
    ELSIF recipe.procedures IS NULL OR ARRAY_LENGTH(recipe.procedures) = 0
        THEN return json_build_object('status', false, 'error', 'Cooking steps are not provided');
    ELSIF recipe.ingredients IS NULL OR ARRAY_LENGTH(recipe.ingredients) = 0
        THEN return json_build_object('status', false, 'error', 'Ingrdients are not provided');
    ELSE
        return json_build_object('status', true, 'error', '');
    END IF;
END
$$;
CREATE FUNCTION ingredient."nutritionalInfo"(sachet ingredient."ingredientSachet") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
BEGIN
    SELECT ingredient."sachetNutritionalInfo"(sachet.id) into info;
    RETURN info;
END
$$;
CREATE FUNCTION ingredient."sachetCost"(sachetid integer) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    sachet record;
    mofId int;
    temp numeric;
BEGIN
    SELECT * FROM ingredient."ingredientSachet" WHERE id = sachetId INTO sachet;
    SELECT id FROM ingredient."modeOfFulfillment" WHERE "ingredientSachetId" = sachetId ORDER BY COALESCE(position, id) DESC LIMIT 1 INTO mofId;
    SELECT ingredient."MOFCost"(mofId) INTO temp;
    IF temp IS NULL OR temp = 0
        THEN SELECT "cost"->'value' FROM ingredient."ingredientProcessing" WHERE id = sachet."ingredientProcessingId" INTO temp;
    END IF;
    IF temp IS NULL
        THEN RETURN 0;
    ELSE
        RETURN temp*sachet.quantity;
    END IF;
END
$$;
CREATE FUNCTION ingredient."sachetNutritionalInfo"(sachet ingredient."ingredientSachet") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
BEGIN
    SELECT "nutritionalInfo" FROM ingredient."ingredientProcessing" WHERE id = sachet."ingredientProcessingId" into info;
    RETURN info;
END
$$;
CREATE FUNCTION ingredient."sachetNutritionalInfo"(sachetid integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    info jsonb;
    sachet record;
    mofId int;
    per numeric;
BEGIN
    SELECT * FROM ingredient."ingredientSachet" WHERE id = sachetId INTO sachet;
    -- order by position and not id
    SELECT id FROM ingredient."modeOfFulfillment" WHERE "ingredientSachetId" = sachetId ORDER BY id DESC NULLS LAST LIMIT 1 INTO mofId;
    SELECT ingredient."MOFNutritionalInfo"(mofId) INTO info;
    IF info IS NULL
        THEN SELECT "nutritionalInfo" FROM ingredient."ingredientProcessing" WHERE id = sachet."ingredientProcessingId" INTO info;
    END IF;
    IF info IS NULL
        THEN RETURN info;
    ELSE
        SELECT COALESCE((info->>'per')::numeric, 1) into per;
        RETURN json_build_object(
            'per', per,
            'iron', COALESCE((info->>'iron')::numeric, 0) * (sachet.quantity)::numeric/per,
            'sodium', COALESCE((info->>'sodium')::numeric, 0) * (sachet.quantity)::numeric/per,
            'sugars', COALESCE((info->>'sugars')::numeric, 0) * (sachet.quantity)::numeric/per,
            'calcium', COALESCE((info->>'calcium')::numeric, 0) * (sachet.quantity)::numeric/per,
            'protein', COALESCE((info->>'protein')::numeric, 0) * (sachet.quantity)::numeric/per,
            'calories', COALESCE((info->>'calories')::numeric, 0) * (sachet.quantity)::numeric/per,
            'totalFat', COALESCE((info->>'totalFat')::numeric, 0) * (sachet.quantity)::numeric/per,
            'transFat', COALESCE((info->>'transFat')::numeric, 0) * (sachet.quantity)::numeric/per,
            'vitaminA', COALESCE((info->>'vitaminA')::numeric, 0) * (sachet.quantity)::numeric/per,
            'vitaminC', COALESCE((info->>'vitaminC')::numeric, 0) * (sachet.quantity)::numeric/per,
            'cholesterol', COALESCE((info->>'cholesterol')::numeric, 0) * (sachet.quantity)::numeric/per,
            'dietaryFibre', COALESCE((info->>'dietaryFibre')::numeric, 0) * (sachet.quantity)::numeric/per,
            'saturatedFat', COALESCE((info->>'saturatedFat')::numeric, 0) * (sachet.quantity)::numeric/per,
            'totalCarbohydrates', COALESCE((info->>'totalCarbohydrates')::numeric, 0) * (sachet.quantity)::numeric/per
        );
    END IF;
END
$$;
CREATE FUNCTION ingredient.sachetvalidity(sachet ingredient."ingredientSachet") RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(sachet.unit IS NULL OR sachet.quantity <= 0)
$$;
CREATE FUNCTION ingredient."set_current_timestamp_updatedAt"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updatedAt" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION ingredient.set_current_timestamp_updated_at() RETURNS trigger
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
CREATE FUNCTION ingredient.twiceq(sachet ingredient."ingredientSachet") RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
  SELECT sachet.quantity*2
$$;
CREATE FUNCTION ingredient."updateModeOfFulfillment"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    update "ingredient"."modeOfFulfillment"
   SET "ingredientId" = (select "ingredientId" from "ingredient"."ingredientSachet" where id = NEW."ingredientSachetId"),
      "ingredientProcessingId" = (select "ingredientProcessingId" from "ingredient"."ingredientSachet" where id = NEW."ingredientSachetId");
    RETURN NULL;
END;
$$;
CREATE FUNCTION ingredient.validity(sachet ingredient."ingredientSachet") RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT NOT(sachet.unit IS NULL OR sachet.quantity <= 0)
$$;
CREATE FUNCTION insights.set_current_timestamp_updated_at() RETURNS trigger
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
CREATE FUNCTION inventory."customToCustomUnitConverter"(quantity numeric, unit_id integer, bulkdensity numeric DEFAULT 1, unit_to_id integer DEFAULT NULL::integer) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$ 
DECLARE 
from_custom_rule record;
to_custom_rule record;
result jsonb := '{"error": null, "result": null}'::jsonb;
proceed text := NULL;
from_in_standard jsonb;
BEGIN  
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE id = unit_to_id
    into to_custom_rule;
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE id = unit_id
    into from_custom_rule;
  IF to_custom_rule IS NULL THEN
    proceed := 'to_unit';
  ELSEIF from_custom_rule IS NULL THEN
    proceed := 'from_unit';
  END IF;
  IF proceed IS NULL THEN
    SELECT data->'result'->'custom'->from_custom_rule.input_unit
      FROM inventory."unitVariationFunc"(quantity, from_custom_rule.input_unit, (-1)::numeric, to_custom_rule.output_unit::text, unit_id) 
      INTO from_in_standard;
    SELECT data 
      FROM inventory."standardToCustomUnitConverter"(
        (from_in_standard->'equivalentValue')::numeric, 
        (from_in_standard->>'toUnitName')::text, 
        (-1)::numeric, 
        unit_to_id
      )
      INTO result;
    result := jsonb_build_object(
      'error', 
      'null'::jsonb,
      'result',
      jsonb_build_object(
        'value',
        quantity,
        'toUnitName',
        to_custom_rule.input_unit,
        'fromUnitName',
        from_custom_rule.input_unit,
        'equivalentValue',
        (result->'result'->'equivalentValue')::numeric
      )
    );
  ELSEIF proceed = 'to_unit' THEN
    result := 
      format('{"error": "no custom unit is defined with the id: %s for argument to_unit, create a conversion rule in the master.\"unitConversion\" table."}', unit_to_id)::jsonb;
  ELSEIF proceed = 'from_unit' THEN
    result := 
      format('{"error": "no custom unit is defined with the id: %s for argument from_unit, create a conversion rule in the master.\"unitConversion\" table."}', unit_id)::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;
CREATE FUNCTION inventory."customToCustomUnitConverter"(quantity numeric, unit text, bulkdensity numeric DEFAULT 1, unitto text DEFAULT NULL::text) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$ 
DECLARE 
from_custom_rule record;
to_custom_rule record;
result jsonb := '{"error": null, "result": null}'::jsonb;
proceed text := NULL;
from_in_standard jsonb;
BEGIN  
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE "inputUnitName" = unitTo
    into to_custom_rule;
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE "inputUnitName" = unit
    into from_custom_rule;
  IF to_custom_rule IS NULL THEN
    proceed := 'to_unit';
  ELSEIF from_custom_rule IS NULL THEN
    proceed := 'from_unit';
  END IF;
  IF proceed IS NULL THEN
    SELECT data->'result'->'custom'->unit
      FROM inventory."unitVariationFunc"('tablename', quantity, unit, -1, to_custom_rule.output_unit::text) 
      INTO from_in_standard;
    SELECT data 
      FROM inventory."standardToCustomUnitConverter"((from_in_standard->'equivalentValue')::numeric, (from_in_standard->>'toUnitName')::text, -1, unitTo)
      INTO result;
    result := jsonb_build_object(
      'error', 
      'null'::jsonb,
      'result',
      jsonb_build_object(
        'value',
        quantity,
        'toUnitName',
        unitTo,
        'fromUnitName',
        unit,
        'equivalentValue',
        (result->'result'->'equivalentValue')::numeric
      )
    );
  ELSEIF proceed = 'to_unit' THEN
    result := 
      format('{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}', unitTo::text)::jsonb;
  ELSEIF proceed = 'from_unit' THEN
    result := 
      format('{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}', unit::text)::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;
CREATE FUNCTION inventory."customUnitVariationFunc"(quantity numeric, unit_id integer, tounit text DEFAULT NULL::text) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
result jsonb;
custom_conversions jsonb;
standard_conversions jsonb;
custom_unit_definition record;
BEGIN 
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE id = unit_id
    into custom_unit_definition;
  If custom_unit_definition IS NOT NULL THEN
    custom_conversions := 
        jsonb_build_object(
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
    SELECT data->'result'->'standard' 
      FROM inventory."unitVariationFunc"(quantity * custom_unit_definition.conversion_factor, custom_unit_definition.output_unit, -1, toUnit) 
      INTO standard_conversions;
  ELSE 
    result := 
      format('{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}', custom_unit_definition.input_unit)::jsonb;
  END IF;
  result :=
    jsonb_build_object(
      'error',
      result->>'error',
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
END
$$;
CREATE FUNCTION inventory."customUnitVariationFunc"(quantity numeric, customunit text, tounit text DEFAULT NULL::text) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
result jsonb;
custom_conversions jsonb;
standard_conversions jsonb;
custom_unit_definition record;
BEGIN 
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE "inputUnitName" = customUnit
    into custom_unit_definition;
  If custom_unit_definition IS NOT NULL THEN
    custom_conversions := 
        jsonb_build_object(customUnit, jsonb_build_object(
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
    SELECT data->'result'->'standard' 
      FROM inventory."unitVariationFunc"('tablename', quantity * custom_unit_definition.conversion_factor, custom_unit_definition.output_unit, -1, toUnit) 
      INTO standard_conversions;
  ELSE 
    result := 
      format('{"error": "no custom unit is defined with the name: %s, create a conversion rule in the master.\"unitConversion\" table."}', customUnit)::jsonb;
  END IF;
  result :=
    jsonb_build_object(
      'error',
      result->>'error',
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
END
$$;
CREATE FUNCTION inventory.custom_to_custom_unit_converter(quantity numeric, from_unit text, from_bulk_density numeric, to_unit text, to_unit_bulk_density numeric, from_unit_id integer, to_unit_id integer) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$ 
DECLARE 
from_custom_rule record;
to_custom_rule record;
result jsonb := '{"error": null, "result": null}'::jsonb;
proceed text := NULL;
from_in_standard jsonb;
BEGIN  
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE id = to_unit_id
    into to_custom_rule;
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE id = from_unit_id
    into from_custom_rule;
  IF to_custom_rule IS NULL THEN
    proceed := 'to_unit';
  ELSEIF from_custom_rule IS NULL THEN
    proceed := 'from_unit';
  END IF;
  IF proceed IS NULL THEN
    SELECT data->'result'->'custom'->from_custom_rule.input_unit
      FROM inventory.custom_to_standard_unit_converter(
        quantity, 
        from_custom_rule.input_unit, 
        from_bulk_density,
        to_custom_rule.output_unit::text, 
        to_unit_bulk_density,
        from_unit_id,
        '',
        '',
        0
      ) INTO from_in_standard;
    SELECT data 
      FROM inventory.standard_to_custom_unit_converter(
        (from_in_standard->'equivalentValue')::numeric, 
        (from_in_standard->>'toUnitName')::text, 
        from_bulk_density,
        to_unit,
        to_unit_bulk_density,
        to_unit_id
      ) INTO result;
    result := jsonb_build_object(
      'error', 
      'null'::jsonb,
      'result',
      jsonb_build_object(
        'value',
        quantity,
        'toUnitName',
        to_unit,
        'fromUnitName',
        from_unit,
        'equivalentValue',
        (result->'result'->'equivalentValue')::numeric
      )
    );
  ELSEIF proceed = 'to_unit' THEN
    result := 
      format(
        '{"error": "no custom unit is defined with the id: %s for argument to_unit, create a conversion rule in the master.\"unitConversion\" table."}', 
        to_unit_id
      )::jsonb;
  ELSEIF proceed = 'from_unit' THEN
    result := 
      format(
        '{"error": "no custom unit is defined with the id: %s for argument from_unit, create a conversion rule in the master.\"unitConversion\" table."}', 
        from_unit_id
      )::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;
CREATE FUNCTION inventory.custom_to_standard_unit_converter(quantity numeric, from_unit text, from_bulk_density numeric, to_unit text, to_unit_bulk_density numeric, unit_conversion_id integer, schemaname text, tablename text, entity_id integer) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
result jsonb;
custom_conversions jsonb;
standard_conversions jsonb;
custom_unit_definition record;
BEGIN 
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE id = unit_conversion_id
    into custom_unit_definition;
  If custom_unit_definition IS NOT NULL THEN
    custom_conversions := 
      jsonb_build_object(
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
    SELECT data->'result'
      FROM inventory.standard_to_standard_unit_converter(
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
  ELSE 
    result := 
      format(
        '{"error": "no custom unit is defined with the id: %s and name: %s, create a conversion rule in the master.\"unitConversion\" table."}', 
        unit_conversion_id,
        from_unit
      )::jsonb;
  END IF;
  result :=
    jsonb_build_object(
      'error',
      result->>'error',
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
$$;
CREATE FUNCTION inventory."matchIngredientIngredient"(ingredients jsonb, ingredientids integer[]) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
ingredient_i record;
ingredient record;
result jsonb;
arr jsonb := '[]';
matched_ingredient jsonb;
BEGIN
  IF ingredientIds IS NOT NULL THEN
    FOR ingredient_i IN 
      SELECT name, id FROM ingredient.ingredient 
      WHERE name IS NOT NULL 
      AND id = ANY(ingredientIds) LOOP
      SELECT * FROM jsonb_array_elements(ingredients) AS found_ingredient
      WHERE (found_ingredient ->> 'ingredientName')::text = ingredient_i.name 
      into matched_ingredient;
      IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
          'ingredient',
          matched_ingredient,
          'ingredientId',
          ingredient_i.id
        ); 
      END IF;
    END LOOP;
  ELSE 
    FOR ingredient_i IN 
      SELECT name, id FROM ingredient.ingredient 
      WHERE name IS NOT NULL 
    LOOP
      SELECT * FROM jsonb_array_elements(ingredients) AS found_ingredient
      WHERE (found_ingredient ->> 'ingredientName')::text = ingredient_i.name 
      into matched_ingredient;
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
$$;
CREATE FUNCTION inventory."matchIngredientSachetItem"(ingredients jsonb, supplieriteminputs integer[]) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE supplier_item record;
result jsonb;
arr jsonb := '[]';
matched_ingredient jsonb;
BEGIN IF supplierItemInputs IS NOT NULL THEN FOR supplier_item IN
SELECT "sachetItem".id sachet_id,
  "supplierItem".id,
  "supplierItem".name
FROM inventory."sachetItem"
  Inner JOIN inventory."bulkItem" ON "bulkItemId" = "bulkItem"."id"
  Inner JOIN inventory."supplierItem" ON "supplierItemId" = "supplierItem"."id"
WHERE "supplierItem".id = ANY (supplierItemInputs) LOOP
SELECT *
FROM jsonb_array_elements(ingredients) AS found_ingredient
WHERE (found_ingredient->>'ingredientName') = supplier_item.name INTO matched_ingredient;
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
SELECT "sachetItem".id sachet_id,
  "supplierItem".id,
  "supplierItem".name
FROM inventory."sachetItem"
  Inner JOIN inventory."bulkItem" ON "bulkItemId" = "bulkItem"."id"
  Inner JOIN inventory."supplierItem" ON "supplierItemId" = "supplierItem"."id" LOOP
SELECT *
FROM jsonb_array_elements(ingredients) AS found_ingredient
WHERE (found_ingredient->>'ingredientName') = supplier_item.name INTO matched_ingredient;
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
SELECT 1 AS id,
  result as data;
END;
$$;
CREATE FUNCTION inventory."matchIngredientSupplierItem"(ingredients jsonb, supplieriteminputs integer[]) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE supplier_item record;
ingredient record;
result jsonb;
arr jsonb := '[]';
matched_ingredient jsonb;
BEGIN IF supplierItemInputs IS NOT NULL THEN FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name"
FROM inventory."supplierItem"
WHERE "supplierItem".id = ANY (supplierItemInputs) LOOP
SELECT *
FROM jsonb_array_elements(ingredients) AS found_ingredient
WHERE (found_ingredient->>'ingredientName') = supplier_item.name INTO matched_ingredient;
IF matched_ingredient IS NOT NULL THEN arr := arr || jsonb_build_object(
  'ingredient',
  matched_ingredient,
  'supplierItemId',
  supplier_item.id
);
END IF;
END LOOP;
ELSE FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name"
FROM inventory."supplierItem" LOOP
SELECT *
FROM jsonb_array_elements(ingredients) AS found_ingredient
WHERE (found_ingredient->>'ingredientName') = supplier_item.name INTO matched_ingredient;
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
SELECT 1 AS id,
  result as data;
END;
$$;
CREATE FUNCTION inventory."matchSachetIngredientSachet"(sachets jsonb, ingredientsachetids integer[]) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$ 
DECLARE sachet_ingredient record;
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
$$;
CREATE FUNCTION inventory."matchSachetSachetItem"(sachets jsonb, sachetitemids integer[]) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE supplier_item record;
sachet record;
result jsonb;
arr jsonb := '[]';
matched_sachet jsonb;
BEGIN IF sachetItemIds IS NOT NULL THEN FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name",
  "processingName",
  "bulkItem".id "processingId",
  "sachetItem"."unitSize",
  "sachetItem"."unit",
  "sachetItem".id sachet_item_id
FROM inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "supplierItem"."id" = "bulkItem"."supplierItemId"
  LEFT JOIN inventory."sachetItem" ON "sachetItem"."bulkItemId" = "bulkItem"."id"
WHERE "sachetItem"."unitSize" IS NOT NULL
  AND "sachetItem".id = ANY (sachetItemIds) LOOP
SELECT *
FROM jsonb_array_elements(sachets) AS found_sachet
WHERE (found_sachet->>'quantity')::int = supplier_item."unitSize"
  AND (found_sachet->>'processingName') = supplier_item."processingName"
  AND (found_sachet->>'ingredientName') = supplier_item.name INTO matched_sachet;
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
SELECT "supplierItem".id,
  "supplierItem"."name",
  "processingName",
  "bulkItem".id "processingId",
  "sachetItem"."unitSize",
  "sachetItem"."unit",
  "sachetItem"."id" sachet_item_id
FROM inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "supplierItem"."id" = "bulkItem"."supplierItemId"
  LEFT JOIN inventory."sachetItem" ON "sachetItem"."bulkItemId" = "bulkItem"."id"
WHERE "sachetItem"."unitSize" IS NOT NULL
  AND "processingName" IS NOT NULL LOOP
SELECT *
FROM jsonb_array_elements(sachets) AS found_sachet
WHERE (found_sachet->>'quantity')::int = supplier_item."unitSize"
  AND (found_sachet->>'processingName') = supplier_item."processingName"
  AND (found_sachet->>'ingredientName') = supplier_item.name INTO matched_sachet;
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
SELECT 1 AS id,
  result as data;
END;
$$;
CREATE FUNCTION inventory."matchSachetSupplierItem"(sachets jsonb, supplieriteminputs integer[]) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE supplier_item record;
sachet record;
result jsonb;
arr jsonb := '[]';
matched_sachet jsonb;
BEGIN IF supplierItemInputs IS NOT NULL THEN FOR supplier_item IN
SELECT "supplierItem".id,
  "supplierItem"."name",
  "supplierItem"."unitSize",
  "supplierItem".unit,
  "processingName"
FROM inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "bulkItemAsShippedId" = "bulkItem"."id"
WHERE "supplierItem".id = ANY (supplierItemInputs) LOOP
SELECT *
FROM jsonb_array_elements(sachets) AS found_sachet
WHERE (found_sachet->>'quantity')::int = supplier_item."unitSize"
  AND (found_sachet->>'processingName') = supplier_item."processingName"
  AND (found_sachet->>'ingredientName') = supplier_item.name INTO matched_sachet;
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
SELECT "supplierItem".id,
  "supplierItem"."name",
  "supplierItem"."unitSize",
  "supplierItem".unit,
  "processingName"
FROM inventory."supplierItem"
  LEFT JOIN inventory."bulkItem" ON "bulkItemAsShippedId" = "bulkItem"."id"
WHERE "processingName" IS NOT NULL LOOP
SELECT *
FROM jsonb_array_elements(sachets) AS found_sachet
WHERE (found_sachet->>'quantity')::int = supplier_item."unitSize"
  AND (found_sachet->>'processingName') = supplier_item."processingName"
  AND (found_sachet->>'ingredientName') = supplier_item.name INTO matched_sachet;
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
SELECT 1 AS id,
  result as data;
END;
$$;
CREATE FUNCTION inventory."set_current_timestamp_updatedAt"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updatedAt" = NOW();
  RETURN _new;
END;
$$;
CREATE FUNCTION inventory.set_current_timestamp_updated_at() RETURNS trigger
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
CREATE FUNCTION inventory."standardToCustomUnitConverter"(quantity numeric, unit text, bulkdensity numeric DEFAULT 1, unit_to_id numeric DEFAULT NULL::numeric) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$ 
DECLARE 
result jsonb := '{"error": null, "result": null}'::jsonb;
custom_rule record;
converted_standard jsonb;
BEGIN  
  -- unit_to_id is the id of a custom rule in master."unitConversion"
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE id = unit_to_id
    into custom_rule;
  IF custom_rule IS NOT NULL THEN
    SELECT data FROM inventory."unitVariationFunc"(quantity, unit, (-1)::numeric, custom_rule.output_unit, -1) into converted_standard;
    result := jsonb_build_object(
      'error', 
      'null'::jsonb, 
      'result', 
      jsonb_build_object(
        'fromUnitName', 
        unit, 
        'toUnitName', 
        custom_rule.input_unit,
        'value',
        quantity,
        'equivalentValue',
        (converted_standard->'result'->'standard'->custom_rule.output_unit->>'equivalentValue')::numeric / custom_rule.conversion_factor
    ));
  ELSE
    -- costruct an error msg
    result := 
      format('{"error": "no custom unit is defined with the id: %s, create a conversion rule in the master.\"unitConversion\" table."}', unit_to_id)::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;
CREATE FUNCTION inventory.standard_to_all_converter(quantity numeric, from_unit text, from_bulk_density numeric, tablename text, entity_id integer, all_mode text DEFAULT 'all'::text) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $_$ 
DECLARE 
definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$;
unit_key record;
custom_unit_key record;
from_definition jsonb;
local_result jsonb;
result_standard jsonb := '{}'::jsonb;
result_custom jsonb := '{}'::jsonb;
result jsonb := '{"error": null, "result": null}'::jsonb;
converted_value numeric;
BEGIN  
  IF all_mode = 'standard' OR all_mode = 'all' THEN
    from_definition := definitions -> from_unit;
    FOR unit_key IN SELECT key, value FROM jsonb_each(definitions) LOOP
      -- unit_key is definition from definitions.
      IF unit_key.value -> 'bulkDensity' THEN
        -- to is volume
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume too
          converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
        ELSE
          -- from is mass
          converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric / (unit_key.value->>'bulkDensity')::numeric;
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
      ELSE
        -- to is mass
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume 
          converted_value := quantity *  (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric * (from_unit_bulk_density)::numeric;
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
        ELSE
          -- from is mass too
          converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
  ELSEIF all_mode = 'custom' OR all_mode = 'all' THEN
    FOR custom_unit_key IN
      EXECUTE format(
        $$SELECT 
          "inputUnitName" input_unit, 
          "outputUnitName" output_unit, 
          "conversionFactor" conversion_factor, 
          "unitConversionId" unit_conversion_id
        FROM %I
        INNER JOIN master."unitConversion"
        ON "unitConversionId" = "unitConversion".id
        WHERE "entityId" = (%s)::integer;$$,
        tablename,
        entity_id
      )
      LOOP
        SELECT data FROM inventory.standard_to_custom_unit_converter(
          quantity,
          from_unit, 
          from_bulk_density,
          custom_unit_key.input_unit,
          (-1)::numeric,
          custom_unit_key.unit_conversion_id
        ) INTO local_result;
        result_custom := result_custom || jsonb_build_object(custom_unit_key.input_unit, local_result);
      END LOOP;
  END IF;
  result := jsonb_build_object(
    'result',
    jsonb_build_object('standard', result_standard, 'custom', result_custom),
    'error',
    'null'::jsonb
  );
RETURN QUERY
SELECT
  1 AS id,
  result as data;
END;
$_$;
CREATE FUNCTION inventory.standard_to_all_converter(quantity numeric, from_unit text, from_bulk_density numeric, schemaname text DEFAULT ''::text, tablename text DEFAULT ''::text, entity_id integer DEFAULT '-1'::integer, all_mode text DEFAULT 'all'::text) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $_$ 
DECLARE 
definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$;
unit_key record;
custom_unit_key record;
from_definition jsonb;
local_result jsonb;
result_standard jsonb := '{}'::jsonb;
result_custom jsonb := '{}'::jsonb;
result jsonb := '{"error": null, "result": null}'::jsonb;
converted_value numeric;
BEGIN  
  IF all_mode = 'standard' OR all_mode = 'all' THEN
    from_definition := definitions -> from_unit;
    FOR unit_key IN SELECT key, value FROM jsonb_each(definitions) LOOP
      -- unit_key is definition from definitions.
      IF unit_key.value -> 'bulkDensity' THEN
        -- to is volume
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume too
          converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
        ELSE
          -- from is mass
          converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric / (unit_key.value->>'bulkDensity')::numeric;
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
      ELSE
        -- to is mass
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume 
          converted_value := quantity *  (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric * (from_unit_bulk_density)::numeric;
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
        ELSE
          -- from is mass too
          converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
  IF all_mode = 'custom' OR all_mode = 'all' THEN
    FOR custom_unit_key IN
      EXECUTE format(
        $$SELECT 
          "inputUnitName" input_unit, 
          "outputUnitName" output_unit, 
          "conversionFactor" conversion_factor, 
          "unitConversionId" unit_conversion_id
        FROM %I.%I
        INNER JOIN master."unitConversion"
        ON "unitConversionId" = "unitConversion".id
        WHERE "entityId" = (%s)::integer;$$,
        schemaname,
        tablename,
        entity_id
      )
      LOOP
        SELECT data FROM inventory.standard_to_custom_unit_converter(
          quantity,
          from_unit, 
          from_bulk_density,
          custom_unit_key.input_unit,
          (1)::numeric,
          custom_unit_key.unit_conversion_id
        ) INTO local_result;
        result_custom := result_custom || jsonb_build_object(custom_unit_key.input_unit, local_result);
      END LOOP;
  END IF;
  result := jsonb_build_object(
    'result',
    jsonb_build_object('standard', result_standard, 'custom', result_custom),
    'error',
    'null'::jsonb
  );
RETURN QUERY
SELECT
  1 AS id,
  result as data;
END;
$_$;
CREATE FUNCTION inventory.standard_to_custom_unit_converter(quantity numeric, from_unit text, from_bulk_density numeric, to_unit text, to_unit_bulk_density numeric, unit_conversion_id integer) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $$ 
DECLARE 
result jsonb := '{"error": null, "result": null}'::jsonb;
custom_rule record;
converted_standard jsonb;
BEGIN  
  -- unit_to_id is the id of a custom rule in master."unitConversion"
  SELECT "inputUnitName" input_unit, "outputUnitName" output_unit, "conversionFactor" conversion_factor 
    FROM master."unitConversion" 
    WHERE id = unit_conversion_id
    into custom_rule;
  IF custom_rule IS NOT NULL THEN
    SELECT data FROM inventory.standard_to_standard_unit_converter(
      quantity, 
      from_unit, 
      from_bulk_density,
      custom_rule.output_unit, 
      to_unit_bulk_density,
      '', -- schemaname
      '', -- tablename
      0 -- entity id
    ) into converted_standard;
    result := jsonb_build_object(
      'error', 
      'null'::jsonb, 
      'result', 
      jsonb_build_object(
        'fromUnitName', 
        from_unit, 
        'toUnitName', 
        custom_rule.input_unit,
        'value',
        quantity,
        'equivalentValue',
        (converted_standard->'result'->'standard'->custom_rule.output_unit->>'equivalentValue')::numeric / custom_rule.conversion_factor
    ));
  ELSE
    -- costruct an error msg
    result := 
      format(
        '{"error": "no custom unit is defined with the id: %s and name: %s, create a conversion rule in the master.\"unitConversion\" table."}', 
        unit_conversion_id,
        to_unit
      )::jsonb;
  END IF;
  RETURN QUERY
  SELECT
    1 AS id,
    result as data;
END;
$$;
CREATE FUNCTION inventory.standard_to_standard_unit_converter(quantity numeric, from_unit text, from_bulk_density numeric, to_unit text, to_unit_bulk_density numeric, schemaname text, tablename text, entity_id integer, all_mode text DEFAULT 'all'::text) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $_$ 
DECLARE 
definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$;
unit_key record;
from_definition jsonb;
to_definition jsonb;
local_result jsonb;
result_standard jsonb := '{}'::jsonb;
result jsonb := '{"error": null, "result": null}'::jsonb;
converted_value numeric;
BEGIN  
  -- 1. get the from definition of this unit;
  from_definition := definitions -> from_unit;
  -- gql forces the value of uni_to, passing '' should work.
  IF to_unit = '' OR to_unit IS NULL THEN 
    -- to_unit is '', convert to all (standard to custom)
    SELECT data from inventory.standard_to_all_converter(
      quantity,
      from_unit, 
      from_bulk_density,
      schemaname,
      tablename,
      entity_id,
      all_mode
    ) INTO result;
  ELSE 
    to_definition := definitions -> to_unit;
    IF to_definition -> 'bulkDensity' THEN
      -- to is volume
      IF from_definition -> 'bulkDensity' THEN
        -- from is volume too
        -- ignore bulkDensity as they should be same in volume to volume of same entity.
        converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
        local_result := jsonb_build_object(
          'fromUnitName',
          from_unit,
          'toUnitName',
          to_definition->'name'->>'abbr',
          'value',
          quantity,
          'equivalentValue',
          converted_value
        );
      ELSE
        -- from is mass
        converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric / (to_unit_bulk_density)::numeric;
        local_result := jsonb_build_object(
          'fromUnitName',
          from_unit,
          'toUnitName',
          to_definition->'name'->>'abbr',
          'value',
          quantity,
          'equivalentValue',
          converted_value
        );
      END IF;
    ELSE
      -- to is mass
      IF from_definition -> 'bulkDensity' THEN
        -- from is volume 
        converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric * (from_bulk_density)::numeric;
        local_result := jsonb_build_object(
          'fromUnitName',
          from_unit,
          'toUnitName',
          to_definition->'name'->>'abbr',
          'value',
          quantity,
          'equivalentValue',
          converted_value
        );
      ELSE
        -- from is mass too
        converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
        local_result := jsonb_build_object(
          'fromUnitName',
          from_unit,
          'toUnitName',
          to_definition->'name'->>'abbr',
          'value',
          quantity,
          'equivalentValue',
          converted_value
        );
      END IF;
    END IF;
  result_standard := result_standard || jsonb_build_object(to_definition->'name'->>'abbr', local_result);
  result := jsonb_build_object(
    'result',
    jsonb_build_object('standard', result_standard),
    'error',
    'null'::jsonb
  );
  END IF;
RETURN QUERY
SELECT
  1 AS id,
  result as data;
END;
$_$;
CREATE FUNCTION inventory."unitVariationFunc"(quantity numeric, unit text DEFAULT NULL::text, bulkdensity numeric DEFAULT 1, unitto text DEFAULT NULL::text, unit_id integer DEFAULT NULL::integer) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $_$ 
DECLARE 
definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$;
known_units text[] := '{kg, g, mg, oz, l, ml}';
unit_key record;
from_definition jsonb;
to_definition jsonb;
local_result jsonb;
result_standard jsonb := '{}'::jsonb;
result jsonb := '{"error": null, "result": null}'::jsonb;
converted_value numeric;
BEGIN  
  IF unit = ANY(known_units) THEN
  -- 1. get the from definition of this unit;
    from_definition := definitions -> unit;
    -- gql forces the value of unitTo, passing '' should work.
    IF unitTo IS NULL OR unitTo = '' THEN
      FOR unit_key IN SELECT key, value FROM jsonb_each(definitions) LOOP
        -- unit_key is definition from definitions.
        IF unit_key.value -> 'bulkDensity' THEN
          -- to is volume
          IF from_definition -> 'bulkDensity' THEN
            -- from is volume too
            converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
          ELSE
            -- from is mass
            converted_value := quantity * (unit_key.value->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
        ELSE
          -- to is mass
          IF from_definition -> 'bulkDensity' THEN
            -- from is volume 
            converted_value := quantity * (from_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
          ELSE
            -- from is mass too
            converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
      IF to_definition -> 'bulkDensity' THEN
        -- to is volume
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume too
          converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
          local_result := jsonb_build_object(
            'fromUnitName',
            unit,
            'toUnitName',
            to_definition->'name'->>'abbr',
            'value',
            quantity,
            'equivalentValue',
            converted_value
          );
        ELSE
          -- from is mass
          converted_value := quantity * (to_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
          local_result := jsonb_build_object(
            'fromUnitName',
            unit,
            'toUnitName',
            to_definition->'name'->>'abbr',
            'value',
            quantity,
            'equivalentValue',
            converted_value
          );
        END IF;
      ELSE
        -- to is mass
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume 
          converted_value := quantity * (from_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
          local_result := jsonb_build_object(
            'fromUnitName',
            unit,
            'toUnitName',
            to_definition->'name'->>'abbr',
            'value',
            quantity,
            'equivalentValue',
            converted_value
          );
        ELSE
          -- from is mass too
          converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
          local_result := jsonb_build_object(
            'fromUnitName',
            unit,
            'toUnitName',
            to_definition->'name'->>'abbr',
            'value',
            quantity,
            'equivalentValue',
            converted_value
          );
        END IF;
      END IF;
    result_standard := result_standard || jsonb_build_object(to_definition->'name'->>'abbr', local_result);
  END IF;
    result := jsonb_build_object(
      'result',
      jsonb_build_object('standard', result_standard),
      'error',
      'null'::jsonb
    );
  ELSE -- @param unit is not in standard_definitions
    IF unit_id IS NULL THEN
      result := jsonb_build_object(
        'error',
        'unit_id must not be null'
      );
    ELSE
      -- check if customConversion is possible with @param unit
      -- inventory."customUnitVariationFunc" also does error handling for us :)
      -- @param unit_id should not be null here
      -- @param unitTo is a standard unit
      SELECT data from inventory."customUnitVariationFunc"(quantity, unit_id, unitTo) into result;
    END IF;
  END IF;
RETURN QUERY
SELECT
  1 AS id,
  result as data;
END;
$_$;
CREATE FUNCTION inventory."unitVariationFunc"(tablename text, quantity numeric, unit text, bulkdensity numeric DEFAULT 1, unitto text DEFAULT NULL::text) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $_$ 
DECLARE 
definitions jsonb := $${"kg":{"name":{"abbr":"kg","singular":"Kilogram","plural":"Kilograms"},"base":"g","factor":1000},
                        "g":{"name":{"abbr":"g","singular":"Gram","plural":"Grams"},"base":"g","factor":1},
                        "mg":{"name":{"abbr":"mg","singular":"Miligram","plural":"MiliGrams"},"base":"g","factor":0.001},
                        "oz":{"name":{"abbr":"oz","singular":"Ounce","plural":"Ounces"},"base":"g","factor":28.3495},
                        "l":{"name":{"abbr":"l","singular":"Litre","plural":"Litres"},"base":"ml","factor":1000,"bulkDensity":1},
                        "ml":{"name":{"abbr":"ml","singular":"Millilitre","plural":"Millilitres"},"base":"ml","factor":1,"bulkDensity":1}
                        }$$;
known_units text[] := '{kg, g, mg, oz, l, ml}';
unit_key record;
from_definition jsonb;
to_definition jsonb;
local_result jsonb;
result_standard jsonb := '{}'::jsonb;
result jsonb := '{"error": null, "result": null}'::jsonb;
converted_value numeric;
BEGIN  
  IF unit = ANY(known_units) THEN
  -- 1. get the from definition of this unit;
    from_definition := definitions -> unit;
    -- gql forces the value of unitTo, passing "" should work.
    IF unitTo IS NULL OR unitTo = '' THEN
    FOR unit_key IN SELECT key, value FROM jsonb_each(definitions) LOOP
      -- unit_key is definition from definitions.
      IF unit_key.value -> 'bulkDensity' THEN
        -- to is volume
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume too
          converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
        ELSE
          -- from is mass
          converted_value := quantity * (unit_key.value->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
      ELSE
        -- to is mass
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume 
          converted_value := quantity * (from_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
        ELSE
          -- from is mass too
          converted_value := quantity * (from_definition->>'factor')::numeric / (unit_key.value->>'factor')::numeric;
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
      IF to_definition -> 'bulkDensity' THEN
        -- to is volume
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume too
          converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
          local_result := jsonb_build_object(
            'fromUnitName',
            unit,
            'toUnitName',
            to_definition->'name'->>'abbr',
            'value',
            quantity,
            'equivalentValue',
            converted_value
          );
        ELSE
          -- from is mass
          converted_value := quantity * (to_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
          local_result := jsonb_build_object(
            'fromUnitName',
            unit,
            'toUnitName',
            to_definition->'name'->>'abbr',
            'value',
            quantity,
            'equivalentValue',
            converted_value
          );
        END IF;
      ELSE
        -- to is mass
        IF from_definition -> 'bulkDensity' THEN
          -- from is volume 
          converted_value := quantity * (from_definition->>'bulkDensity')::numeric * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
          local_result := jsonb_build_object(
            'fromUnitName',
            unit,
            'toUnitName',
            to_definition->'name'->>'abbr',
            'value',
            quantity,
            'equivalentValue',
            converted_value
          );
        ELSE
          -- from is mass too
          converted_value := quantity * (from_definition->>'factor')::numeric / (to_definition->>'factor')::numeric;
          local_result := jsonb_build_object(
            'fromUnitName',
            unit,
            'toUnitName',
            to_definition->'name'->>'abbr',
            'value',
            quantity,
            'equivalentValue',
            converted_value
          );
        END IF;
      END IF;
    result_standard := result_standard || jsonb_build_object(to_definition->'name'->>'abbr', local_result);
  END IF;
  -- TODO: is is_unit_to_custom == true -> handle standard to custom (probably another sql func)
    result := jsonb_build_object(
      'result',
      jsonb_build_object('standard', result_standard),
      'error',
      'null'::jsonb
    );
  ELSE -- @param unit is not in standard_definitions
    -- check if customConversion is possible with @param unit
    -- inventory."customUnitVariationFunc" also does error handling for us :)
    SELECT data from inventory."customUnitVariationFunc"(quantity, unit, unitTo) into result;
  END IF;
RETURN QUERY
SELECT
  1 AS id,
  result as data;
END;
$_$;

CREATE FUNCTION inventory.unit_conversions_supplier_item(item inventory."supplierItem", from_unit text, from_unit_bulk_density numeric, quantity numeric, to_unit text, to_unit_bulk_density numeric) RETURNS SETOF crm."customerData"
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
  local_quantity                   numeric;
  local_from_unit                  text; 
  local_from_unit_bulk_density     numeric; 
  local_to_unit_bulk_density       numeric;
  known_units                      text[] := '{kg, g, mg, oz, l, ml}';
  result                           jsonb;
  custom_to_unit_conversion_id     integer;
  custom_from_unit_conversion_id   integer;
BEGIN
  /* setup */
  -- resolve quantity
  IF quantity IS NULL 
    OR quantity = -1 THEN
    local_quantity := item."unitSize"::numeric;
  ELSE
    local_quantity := quantity;
  END IF;
  -- resolve from_unit
  IF from_unit IS NULL 
    OR from_unit = ''
    THEN
    local_from_unit := item.unit;
  ELSE
    local_from_unit := from_unit;
  END IF;
  -- resolve from_unit_bulk_density
  IF from_unit_bulk_density IS NULL 
    OR from_unit_bulk_density = -1 THEN
    local_from_unit_bulk_density := item."bulkDensity";
  ELSE
    local_from_unit_bulk_density := from_unit_bulk_density;
  END IF;
  -- resolve to_unit_bulk_density
  IF to_unit_bulk_density IS NULL 
    OR to_unit_bulk_density = -1 THEN
    local_to_unit_bulk_density := item."bulkDensity";
  ELSE
    local_to_unit_bulk_density := to_unit_bulk_density;
  END IF;
  IF to_unit <> ALL(known_units) AND to_unit != '' THEN
    EXECUTE format(
      $$SELECT 
        "unitConversionId" unit_conversion_id
      FROM %I.%I
      INNER JOIN master."unitConversion"
      ON "unitConversionId" = "unitConversion".id
      WHERE "entityId" = (%s)::integer
      AND "inputUnitName" = '%s';$$,
      'inventory', -- schema name
      'supplierItem_unitConversion', -- tablename
      item.id,
      to_unit
    ) INTO custom_to_unit_conversion_id;
  END IF;
  IF local_from_unit <> ALL(known_units) THEN
    EXECUTE format(
      $$SELECT 
        "unitConversionId" unit_conversion_id
      FROM %I.%I
      INNER JOIN master."unitConversion"
      ON "unitConversionId" = "unitConversion".id
      WHERE "entityId" = (%s)::integer
      AND "inputUnitName" = '%s';$$,
      'inventory', -- schema name
      'supplierItem_unitConversion', -- tablename
      item.id,
      local_from_unit
    ) INTO custom_from_unit_conversion_id;
  END IF;
  /* end setup */
  IF local_from_unit = ANY(known_units) THEN -- local_from_unit is standard
    IF to_unit = ANY(known_units)
      OR to_unit = ''
      OR to_unit IS NULL THEN -- to_unit is also standard
        SELECT data FROM inventory.standard_to_standard_unit_converter(
          local_quantity, 
          local_from_unit, 
          local_from_unit_bulk_density,
          to_unit,
          local_to_unit_bulk_density,
          'inventory', -- schema name
          'supplierItem_unitConversion', -- tablename
          item.id,
          'all'
        ) INTO result;
    ELSE -- to_unit is custom and not ''
      -- convert from standard to custom
      SELECT data FROM inventory.standard_to_custom_unit_converter(
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
      SELECT data FROM inventory.custom_to_standard_unit_converter(
        local_quantity, 
        local_from_unit, 
        local_from_unit_bulk_density,
        to_unit,
        local_to_unit_bulk_density,
        custom_from_unit_conversion_id,
        'inventory', -- schema name
        'supplierItem_unitConversion', -- tablename
        item.id
      ) INTO result;
    ELSE -- to_unit is also custom and not ''
      SELECT data FROM inventory.custom_to_custom_unit_converter(
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
$_$;
CREATE FUNCTION notifications.set_current_timestamp_updated_at() RETURNS trigger
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

CREATE FUNCTION "onDemand"."getMenu"(params jsonb) RETURNS SETOF "onDemand".menu
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    colId int;
    menu jsonb[] = '{}';
    cleanMenu jsonb[] DEFAULT '{}';
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
    arr int[];
BEGIN
    FOR colId IN SELECT "collectionId" FROM "onDemand"."brand_collection" WHERE "brandId" = (params->>'brandId')::int AND "isActive" = true LOOP
        SELECT "onDemand"."isCollectionValid"(colId, params) INTO isValid;
        -- RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', isValid) AS data;
        IF (isValid->'status')::boolean = true THEN
            FOR productCategory IN SELECT * FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId ORDER BY position DESC NULLS LAST LOOP
                category := jsonb_build_object(
                    'name', productCategory."productCategoryName", 
                    'inventoryProducts', '{}',
                    'simpleRecipeProducts', '{}',
                    'customizableProducts', '{}',
                    'comboProducts', '{}'
                );
                FOR product IN SELECT * FROM "onDemand"."collection_productCategory_product" WHERE "collection_productCategoryId" = productCategory.id ORDER BY position DESC NULLS LAST LOOP
                    IF product."simpleRecipeProductId" IS NOT NULL THEN
                        category := category || jsonb_build_object('simpleRecipeProducts', (REPLACE(REPLACE(category->>'simpleRecipeProducts', ']', '}'), '[', '{'))::int[] || product."simpleRecipeProductId");
                    ELSIF product."inventoryProductId" IS NOT NULL THEN
                        category := category || jsonb_build_object('inventoryProducts', (REPLACE(REPLACE(category->>'inventoryProducts', ']', '}'), '[', '{'))::int[] || product."inventoryProductId");
                    ELSIF product."customizableProductId" IS NOT NULL THEN
                        category := category || jsonb_build_object('customizableProducts', (REPLACE(REPLACE(category->>'customizableProducts', ']', '}'), '[', '{'))::int[] || product."customizableProductId");
                    ELSIF product."comboProductId" IS NOT NULL THEN
                        category := category || jsonb_build_object('comboProducts', (REPLACE(REPLACE(category->>'comboProducts', ']', '}'), '[', '{'))::int[] || product."comboProductId"); 
                    ELSE
                        CONTINUE;
                    END IF;
                    -- RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', product.id) AS data;
                END LOOP;
                -- RETURN QUERY SELECT category->>'name' AS name, category->'comboProducts' AS "comboProducts",  category->'customizableProducts' AS "customizableProducts", category->'simpleRecipeProducts' AS "simpleRecipeProducts", category->'inventoryProducts' AS "inventoryProducts";
                menu := menu || category;
            END LOOP;
        ELSE
            CONTINUE;
        END IF;
    END LOOP;
    -- RETURN;
    FOREACH oldObject IN ARRAY(menu) LOOP
        exists := false;
        i := NULL;
        IF array_length(cleanMenu, 1) IS NOT NULL THEN
            FOR index IN 0..array_length(cleanMenu, 1) LOOP
                IF cleanMenu[index]->>'name' = oldObject->>'name' THEN
                    exists := true;
                    i := index; 
                    EXIT;
                ELSE
                    CONTINUE;
                END IF;
            END LOOP;
        END IF;
        IF exists = true THEN
            cleanMenu[i] := jsonb_build_object(
                'name', cleanMenu[i]->>'name',
                'simpleRecipeProducts', (REPLACE(REPLACE(cleanMenu[i]->>'simpleRecipeProducts', ']', '}'), '[', '{'))::int[] || (REPLACE(REPLACE(oldObject->>'simpleRecipeProducts', ']', '}'), '[', '{'))::int[],
                'inventoryProducts', (REPLACE(REPLACE(cleanMenu[i]->>'inventoryProducts', ']', '}'), '[', '{'))::int[] || (REPLACE(REPLACE(oldObject->>'inventoryProducts', ']', '}'), '[', '{'))::int[],
                'customizableProducts', (REPLACE(REPLACE(cleanMenu[i]->>'customizableProducts', ']', '}'), '[', '{'))::int[] || (REPLACE(REPLACE(oldObject->>'customizableProducts', ']', '}'), '[', '{'))::int[],
                'comboProducts', (REPLACE(REPLACE(cleanMenu[i]->>'comboProducts', ']', '}'), '[', '{'))::int[] || (REPLACE(REPLACE(oldObject->>'comboProducts', ']', '}'), '[', '{'))::int[]
            );
            -- RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', cleanMenu[i]) AS data;
        ELSE
            cleanMenu := cleanMenu || oldObject;
        END IF;
    END LOOP;
    IF array_length(cleanMenu, 1) IS NOT NULL THEN
        FOR index IN 0..array_length(cleanMenu, 1) LOOP
            IF cleanMenu[index]->>'simpleRecipeProducts' = '{}' THEN
                cleanMenu[index] := cleanMenu[index] || jsonb_build_object('simpleRecipeProducts', (cleanMenu[index]->>'simpleRecipeProducts')::int[]);
            END IF;
            IF cleanMenu[index]->>'inventoryProducts' = '{}' THEN
                cleanMenu[index] := cleanMenu[index] || jsonb_build_object('inventoryProducts', (cleanMenu[index]->>'inventoryProducts')::int[]);
            END IF;
            IF cleanMenu[index]->>'customizableProducts' = '{}' THEN
                cleanMenu[index] := cleanMenu[index] || jsonb_build_object('customizableProducts', (cleanMenu[index]->>'customizableProducts')::int[]);
            END IF;
            IF cleanMenu[index]->>'comboProducts' = '{}' THEN
                cleanMenu[index] := cleanMenu[index] || jsonb_build_object('comboProducts', (cleanMenu[index]->>'comboProducts')::int[]);
            END IF;
        END LOOP;
    END IF;
    RETURN QUERY SELECT 1 AS id, jsonb_build_object('menu', cleanMenu) AS data;
END;
$$;
CREATE FUNCTION "onDemand"."getMenuV2"(params jsonb) RETURNS SETOF "onDemand".menu
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    colId int;
    idArr int[];
    menu jsonb[] := '{}';
    object jsonb;
    isValid jsonb;
    category jsonb;
    productCategory record;
    rec record;
    cleanMenu jsonb[] := '{}'; -- without duplicates
    cleanCategory jsonb; -- without duplicates
    categoriesIncluded text[];
    productsIncluded int[];
    updatedProducts int[];
    productId int;
    pos int := 0;
BEGIN
    -- generating menu data from collections
    FOR colId IN SELECT "collectionId" FROM "onDemand"."brand_collection" WHERE "brandId" = (params->>'brandId')::int AND "isActive" = true LOOP
        SELECT "onDemand"."isCollectionValid"(colId, params) INTO isValid;
        IF (isValid->'status')::boolean = true THEN
            FOR productCategory IN SELECT * FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId ORDER BY position DESC NULLS LAST LOOP
                idArr := '{}'::int[];
                FOR rec IN SELECT * FROM "onDemand"."collection_productCategory_product" WHERE "collection_productCategoryId" = productCategory.id ORDER BY position DESC NULLS LAST LOOP
                    idArr := idArr || rec."productId";
                END LOOP;
                category := jsonb_build_object(
                    'name', productCategory."productCategoryName",
                    'products', idArr
                );
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
            updatedProducts := '{}'::int[];
            productsIncluded := '{}'::int[];
            FOR productId IN SELECT * FROM JSONB_ARRAY_ELEMENTS(cleanMenu[pos]->'products') LOOP
                updatedProducts := updatedProducts || productId;
                productsIncluded := productsIncluded || productId; -- wil remove same products under same category in different collections
            END LOOP;
            FOR productId IN SELECT * FROM JSONB_ARRAY_ELEMENTS(category->'products') LOOP
                IF ARRAY_POSITION(productsIncluded, productId) >= 0 THEN
                    CONTINUE;
                ELSE
                   updatedProducts := updatedProducts || productId;
                   productsIncluded := productsIncluded || productId; -- will remove same products under same category in same collection
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
$$;
CREATE FUNCTION "onDemand"."getOnlineStoreProduct"(productid integer, producttype text) RETURNS SETOF "onDemand".menu
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb;
BEGIN
  IF producttype = 'simpleRecipeProduct' THEN
        SELECT products."getOnlineStoreSRPProduct"(productid) INTO res;
    ELSIF producttype = 'inventoryProduct' THEN
        SELECT products."getOnlineStoreIPProduct"(productid) INTO res;
    ELSIF producttype = 'customizableProduct' THEN
        SELECT products."getOnlineStoreCUSPProduct"(productid) INTO res;
    ELSE
        SELECT products."getOnlineStoreCOMPProduct"(productid) INTO res;
    END IF;
    RETURN QUERY SELECT 1 AS id, res AS data;
END;
$$;

CREATE FUNCTION "onDemand"."getProductDetails"(rec "onDemand"."collection_productCategory_product") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    product record;
    productName text;
    productType text;
    productImage text;
BEGIN
    IF rec."simpleRecipeProductId" IS NOT NULL THEN
        SELECT * FROM products."simpleRecipeProduct" WHERE id = rec."simpleRecipeProductId" INTO product;
        productName := product.name;
        productType := 'simpleRecipeProduct';
        IF product.assets IS NOT NULL AND JSONB_ARRAY_LENGTH(product.assets->'images') > 0 THEN
            productImage := product.assets->'images'#>>'{0}';
        ELSE
            productImage := NULL;
        END IF;
    ELSIF rec."inventoryProductId" IS NOT NULL THEN
        SELECT * FROM products."inventoryProduct" WHERE id = rec."inventoryProductId" INTO product;
        productName := product.name;
        productType := 'inventoryProduct';
        IF product.assets IS NOT NULL AND JSONB_ARRAY_LENGTH(product.assets->'images') > 0 THEN
            productImage := product.assets->'images'#>>'{0}';
        ELSE
            productImage := NULL;
        END IF;
    ELSEIF rec."customizableProductId" IS NOT NULL THEN
        SELECT * FROM products."customizableProduct" WHERE id = rec."customizableProductId" INTO product;
        productName := product.name;
        productType := 'customizableProduct';
        IF product.assets IS NOT NULL AND JSONB_ARRAY_LENGTH(product.assets->'images') > 0 THEN
            productImage := product.assets->'images'#>>'{0}';
        ELSE
            productImage := NULL;
        END IF;
    ELSE
        SELECT * FROM products."comboProduct" WHERE id = rec."comboProductId" INTO product;
        productName := product.name;
        productType := 'comboProduct';
        IF product.assets IS NOT NULL AND JSONB_ARRAY_LENGTH(product.assets->'images') > 0 THEN
            productImage := product.assets->'images'#>>'{0}';
        ELSE
            productImage := NULL;
        END IF;
    END IF;
    RETURN jsonb_build_object(
        'name', productName,
        'type', productType,
        'image', productImage
    );
END
$$;

CREATE FUNCTION "onDemand"."getStoreData"(requestdomain text) RETURNS SETOF "onDemand"."storeData"
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    brandId int;
    settings jsonb;
BEGIN
    SELECT id FROM brands.brand WHERE "domain" = requestDomain INTO brandId; 
    IF brandId IS NULL THEN
        SELECT id FROM brands.brand WHERE "isDefault" = true INTO brandId;
    END IF;
    SELECT brands."getSettings"(brandId) INTO settings;
    RETURN QUERY SELECT 1 AS id, brandId AS brandId, settings as settings;
END;
$$;
CREATE FUNCTION "onDemand"."isCollectionValid"(collectionid integer, params jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb;
    collection record;
    isValid boolean := false;
BEGIN
    IF params->>'date' IS NOT NULL THEN
        SELECT * FROM "onDemand"."collection" WHERE id = collectionId INTO collection;
        IF collection."rrule" IS NOT NULL THEN
            SELECT rules."rruleHasDateFunc"(collection."rrule"::_rrule.rruleset, (params->>'date')::timestamp) INTO isValid;
        ELSE
            isValid := true;
        END IF;
    END IF;
    res := jsonb_build_object('status', isValid);
    return res;
END;
$$;

CREATE FUNCTION "onDemand"."modifierCategoryOptionCartItem"(option "onDemand"."modifierCategoryOption") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    -- counter := option.quantity;
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
    RETURN jsonb_build_object('data', jsonb_build_array(jsonb_build_object('unitPrice', option.price, 'modifierOptionId', option.id)));
END;
$$;
CREATE FUNCTION "onDemand"."numberOfCategories"(colid integer) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res int;
BEGIN
    SELECT COUNT(*) FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId INTO res;
    RETURN res;
END;
$$;
CREATE FUNCTION "onDemand"."numberOfProducts"(colid integer) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    arr int[] := '{}';
    res int;
    rec record;
BEGIN
    FOR rec IN SELECT id FROM "onDemand"."collection_productCategory" WHERE "collectionId" = colId LOOP
        arr := arr || rec.id;
    END LOOP;
    SELECT COUNT(*) FROM "onDemand"."collection_productCategory_product" WHERE "collection_productCategoryId" = ANY(arr) INTO res;
    return res;
END;
$$;
CREATE FUNCTION "onDemand".set_current_timestamp_updated_at() RETURNS trigger
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






CREATE FUNCTION products."isProductValid"(product products.product) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    component record;
    isValid boolean := true;
    message text := '';
    counter int := 0;
BEGIN
    RETURN jsonb_build_object('status', isValid, 'error', message);
END
$$;




CREATE FUNCTION products."productOptionCartItem"(option products."productOption") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
    product products."product";
BEGIN
    SELECT * FROM products.product WHERE id = option."productId" INTO product;
    counter := option.quantity;
    IF option."simpleRecipeYieldId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    RETURN json_build_object(
        'productId', product.id,
        'unitPrice', product.price,
        'childs', jsonb_build_object(
            'data', json_build_array(
                json_build_object (
                    'productOptionId', option.id,
                    'unitPrice', option.price,
                    'childs', json_build_object(
                        'data', items
                    )
                )
            )
        )
    );
END;
$$;


CREATE FUNCTION products.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION products."unpublishProduct"(producttype text, productid integer) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    query text;
BEGIN
    query := 'UPDATE products.' || '"' || productType || '"' || ' SET "isPublished" = false WHERE id = ' || productId;
    EXECUTE query;
END
$$;


CREATE FUNCTION public.call(text) RETURNS jsonb LANGUAGE plpgsql AS $_$
DECLARE
    res jsonb;
BEGIN
    EXECUTE $1 INTO res;
    RETURN res;
END;
$_$;


CREATE FUNCTION public.exec(text) RETURNS boolean LANGUAGE plpgsql AS $_$
DECLARE
    res boolean;
BEGIN
    EXECUTE $1 INTO res;
    RETURN res;
END;
$_$;


CREATE FUNCTION rules."assertFact"(condition jsonb,
                                   params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."budgetFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."cartComboProduct"(fact rules.facts,
                                         params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartComboProductFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartComboProductComponent"(fact rules.facts,
                                                  params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartComboProductComponentFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartComboProductComponentFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartComboProduct', 'fact', 'cartComboProduct', 'title', 'Cart Contains Combo Product Component', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  comboProductComponents { id } }" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."cartComboProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."cartContainsAddOnProducts"(fact rules.facts,
                                                  params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartContainsAddOnProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartContainsAddOnProductsFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."cartCustomizableProduct"(fact rules.facts,
                                                params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartCustomizableProductFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartCustomizableProductComponent"(fact rules.facts,
                                                         params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartCustomizableProductComponentFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartCustomizableProductComponentFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartCustomizableProduct', 'fact', 'cartCustomizableProduct', 'title', 'Cart Contains Combo Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  CustomizableProductComponents { id } }" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."cartCustomizableProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."cartInventoryProductOption"(fact rules.facts,
                                                   params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartInventoryProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartInventoryProductOptionFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartInventoryProductOption', 'fact', 'cartInventoryProductOption', 'title', 'Cart Contains Inventory Product Option', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"inventory\"}}) { id } }" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."cartItemTotal"(fact rules.facts,
                                      params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartItemTotalFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartItemTotalFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    total numeric;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF (params->>'read')::boolean = true
        THEN RETURN json_build_object('id', 'cartItemTotal', 'fact', 'cartItemTotal', 'title', 'Cart Item Total', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        SELECT COALESCE((SELECT SUM("unitPrice") FROM "order"."cartItem" WHERE id = (params->>'cartId')::integer), 0) INTO total;
        RETURN json_build_object('value', total, 'valueType','numeric','arguments','cartId');
    END IF;
END;
$$;


CREATE FUNCTION rules."cartMealKitProductOption"(fact rules.facts,
                                                 params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartMealKitProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartMealKitProductOptionFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartMealKitProductOption', 'fact', 'cartMealKitProductOption', 'title', 'Cart Contains Meal Kit Product Option', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"mealKit\"}}) { id } }" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."cartReadyToEatProductOption"(fact rules.facts,
                                                    params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartReadyToEatProductOptionFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartReadyToEatProductOptionFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartReadyToEatProductOption', 'fact', 'cartReadyToEatProductOption', 'title', 'Cart Contains Ready to Eat Product Option', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{  productOptions (where: {type: {_eq: \"readyToEat\"}}) { id } }" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."cartSimpleProduct"(fact rules.facts,
                                          params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartSimpleProductFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartSimpleProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['in','notIn'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'cartSimpleProduct', 'fact', 'cartSimpleProductFunc', 'title', 'Cart Contains Simple Product', 'value', '{ "type" : "select", "select" : "id", "datapoint" : "query", "query" : "{ products(where: {type: {_eq: \"simple\"}}) { id title: name } }" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."cartSubscriptionItemCount"(fact rules.facts,
                                                  params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartSubscriptionItemCountFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartSubscriptionItemCountFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."cartSubscriptionServingSize"(fact rules.facts,
                                                    params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartSubscriptionServingSizeFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartSubscriptionServingSizeFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    subscriptionServingSize int;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('fact', 'subscriptionServingSize', 'title', 'Subscription Serving Size','value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
    ELSE
        select "subscriptionServingSize" into subscriptionServingSize from "subscription"."view_subscription"
        where id = (select "subscriptionId" from "subscription"."subscriptionOccurence"
        where id = (select "subscriptionOccurenceId" from "order"."cart" where id = (params->>'cartId')::integer));
        RETURN jsonb_build_object('value', subscriptionServingSize, 'valueType','integer','argument','cartid');
    END IF;
END;
$$;


CREATE FUNCTION rules."cartSubscriptionTitle"(fact rules.facts,
                                              params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."cartSubscriptionTitleFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."cartSubscriptionTitleFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."checkAllConditions"(conditionarray jsonb,
                                           params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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
      ELSE
          SELECT rules."assertFact"(condition::jsonb, params) INTO tmp;
          SELECT res3 AND tmp INTO res3;
      END IF;
   END LOOP;
  RETURN res1 AND res2 AND res3;
END;
$$;


CREATE FUNCTION rules."checkAnyConditions"(conditionarray jsonb,
                                           params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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
      ELSE
          SELECT rules."assertFact"(condition::jsonb, params) INTO tmp;
          SELECT res3 OR tmp INTO res3;
      END IF;
   END LOOP;
  RETURN res1 OR res2 OR res3;
END;
$$;


CREATE FUNCTION rules."customerEmail"(fact rules.facts,
                                      params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerEmailFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."customerEmailFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."customerReferralCodeFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."customerReferrerCode"(fact rules.facts,
                                             params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerReferrerCodeFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."customerReferrerCodeFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."customerSubscriptionSkipCountWithDuration"(fact rules.facts,
                                                                  params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."customerSubscriptionSkipCountWithDurationFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."customerSubscriptionSkipCountWithDurationFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."getFactValue"(fact text, params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN call('SELECT rules."' || fact || 'Func"' || '(' || '''' || params || '''' || ')');
END;
$$;


CREATE FUNCTION rules."isCartSubscription"(fact rules.facts,
                                           params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."isCartSubscriptionFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."isCartSubscriptionFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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



CREATE FUNCTION rules."isConditionValid"(condition rules.conditions,
                                         params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."isConditionValidFunc"(conditionid integer, params jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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
        SELECT false INTO res;
    END IF;
    RETURN res;
END;
$$;


CREATE FUNCTION rules."isCustomerReferred"(fact rules.facts,
                                           params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."isCustomerReferredFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."isCustomerReferredFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."numberOfCustomerReferred"(fact rules.facts,
                                                 params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfCustomerReferredFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."numberOfCustomerReferredFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."numberOfSubscriptionAddOnProducts"(fact rules.facts,
                                                          params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfSubscriptionAddOnProductsFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."numberOfSubscriptionAddOnProductsFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."numberOfSuccessfulCustomerReferred"(fact rules.facts,
                                                           params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."numberOfSuccessfulCustomerReferredFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."numberOfSuccessfulCustomerReferredFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."orderCountWithDuration"(fact rules.facts,
                                               params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."orderCountWithDurationFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."orderCountWithDurationFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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
          dateArray := ARRAY(SELECT "created_at" FROM "order"."cart" WHERE "customerKeycloakId" = (params->>'keycloakId')::text AND "orderId" IS NOT NULL);
          FOREACH dateArr IN ARRAY dateArray
          LOOP
              IF dateArr > startdate AND dateArr < enddate
                THEN orderCount := orderCount + 1;
              END IF;
          END LOOP;
          RETURN json_build_object('value',orderCount,'valueType','integer','argument','keycloakId');
    END IF;
END;
$$;


CREATE FUNCTION rules."referralStatus"(fact rules.facts,
                                       params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."referralStatusFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."referralStatusFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    referralStatus text ;
     operators text[] := ARRAY['equal', 'notEqual'];
BEGIN
IF params->'read'
        THEN RETURN json_build_object('id', 'referralStatus', 'fact', 'referralStatus', 'title', 'Customer Referral Status', 'value', '{ "type" : "text" }'::json,'argument','keycloakId', 'operators', operators);
    ELSE
          SELECT "referralStatus" FROM crm."customerReferral" WHERE "keycloakId" = (params->>'keycloakId')::text INTO referralStatus;
          RETURN json_build_object('value', referralStatus, 'valueType','text','argument','keycloakId');
    END IF;
END;
$$;


CREATE FUNCTION rules."rruleHasDateFunc"(rrule _rrule.rruleset,
                                         d timestamp without time zone) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
    res boolean;
BEGIN
  SELECT rrule @> d into res;
  RETURN res;
END;
$$;


CREATE FUNCTION rules."runWithOperator"(
                                        operator text, vals jsonb) RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION rules."totalNumberOfCartComboProduct"(fact rules.facts,
                                                      params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartComboProductFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."totalNumberOfCartComboProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfComboProducts', 'fact', 'totalNumberOfComboProducts', 'title', 'Total Number Of Combo Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."totalNumberOfCartCustomizableProduct"(fact rules.facts,
                                                             params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartCustomizableProductFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."totalNumberOfCartCustomizableProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartItem" record;
    productType text;
    productIdArray integer array DEFAULT '{}';
    productId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfCustomizableProducts', 'fact', 'totalNumberOfCustomizableProducts', 'title', 'Total Number Of Customizable Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."totalNumberOfCartInventoryProduct"(fact rules.facts,
                                                          params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartInventoryProductFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."totalNumberOfCartInventoryProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfInventoryProducts', 'fact', 'totalNumberOfInventoryProducts', 'title', 'Total Number Of Ready To Eat Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."totalNumberOfCartMealKitProduct"(fact rules.facts,
                                                        params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartMealKitProductFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."totalNumberOfCartMealKitProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfMealKitProducts', 'fact', 'totalNumberOfMealKitProducts', 'title', 'Total Number Of Meal Kit Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION rules."totalNumberOfCartReadyToEatProduct"(fact rules.facts,
                                                           params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    result jsonb;
BEGIN
  SELECT rules."totalNumberOfCartReadyToEatProductFunc"(params) INTO result;
  RETURN result;
END;
$$;


CREATE FUNCTION rules."totalNumberOfCartReadyToEatProductFunc"(params jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    "cartProduct" record;
    productOptionType text;
    productOptionIdArray integer array DEFAULT '{}';
    productOptionId integer;
    operators text[] := ARRAY['equal', 'greaterThan', 'greaterThanInclusive', 'lessThan', 'lessThanInclusive'];
BEGIN
    IF params->'read'
        THEN RETURN json_build_object('id', 'totalNumberOfReadyToEatProducts', 'fact', 'totalNumberOfReadyToEatProducts', 'title', 'Total Number Of Ready To Eat Products (with Quantity)', 'value', '{ "type" : "int" }'::json,'argument','cartId', 'operators', operators);
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


CREATE FUNCTION safety.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION settings.define_owner_role() RETURNS trigger LANGUAGE plpgsql AS $$
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



CREATE FUNCTION settings."operationConfigName"(opconfig settings."operationConfig") RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
    station text;
    template text;
BEGIN
    SELECT name FROM "deviceHub"."labelTemplate" WHERE id = opConfig."labelTemplateId" INTO template;
    SELECT name FROM settings."station" WHERE id = opConfig."stationId" INTO station;
    RETURN station || ' - ' || template;
END;
$$;


CREATE FUNCTION settings.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION "simpleRecipe"."getRecipeRichResult"(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION "simpleRecipe".issimplerecipevalid(recipe "simpleRecipe"."simpleRecipe") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION "simpleRecipe".set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION "simpleRecipe"."updateSimpleRecipeYield_ingredientSachet"() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
   update "simpleRecipe"."simpleRecipeYield_ingredientSachet"
   SET "simpleRecipeId" = (select "simpleRecipeId" from "simpleRecipe"."simpleRecipeYield" where id = NEW."recipeYieldId");
    RETURN NULL;
END;
$$;


CREATE FUNCTION "simpleRecipe"."yieldAllergens"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION "simpleRecipe"."yieldCost"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION "simpleRecipe"."yieldNutritionalInfo"(yield "simpleRecipe"."simpleRecipeYield") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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



CREATE FUNCTION subscription."addOnCartItem"(x subscription."subscriptionOccurence_addOn") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION subscription."assignWeekNumberToSubscriptionOccurence"("subscriptionOccurenceId" integer) RETURNS integer LANGUAGE plpgsql AS $$
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



CREATE FUNCTION subscription."calculateIsValid"(occurence subscription."subscriptionOccurence") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION subscription."calculateIsVisible"(occurence subscription."subscriptionOccurence") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION subscription."cartItem"(x subscription."subscriptionOccurence_product") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION subscription."customerSubscriptionReport"(brand_customerid integer, status text) RETURNS integer LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION subscription."isCartValid"(record subscription."subscriptionOccurence_customer") RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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



CREATE FUNCTION subscription."isSubscriptionItemCountValid"(itemcount subscription."subscriptionItemCount") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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



CREATE FUNCTION subscription."isSubscriptionServingValid"(serving subscription."subscriptionServing") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION subscription."isSubscriptionTitleValid"(title subscription."subscriptionTitle") RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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


CREATE FUNCTION subscription.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


CREATE FUNCTION subscription."subscriptionOccurenceWeekRank"(record subscription."subscriptionOccurence") RETURNS integer LANGUAGE plpgsql STABLE AS $$
DECLARE
BEGIN
    RETURN "subscription"."assignWeekNumberToSubscriptionOccurence"(record.id);
END
$$;


CREATE FUNCTION subscription."toggleServingState"(servingid integer, state boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE subscription."subscriptionServing"
    SET "isActive" = state
    WHERE "id" = servingId;
END;
$$;


CREATE FUNCTION subscription."toggleTitleState"(titleid integer, state boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE subscription."subscriptionTitle"
    SET "isActive" = state
    WHERE "id" = titleId;
END;
$$;


CREATE FUNCTION subscription."updateSubscription"() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
BEGIN
   UPDATE "subscription"."subscription"
SET "subscriptionTitleId" = (select "subscriptionTitleId" from "subscription"."subscriptionItemCount" where id = NEW."subscriptionItemCountId"),
"subscriptionServingId" = (select "subscriptionServingId" from "subscription"."subscriptionItemCount" where id = NEW."subscriptionItemCountId")
WHERE id = NEW.id;
    RETURN null;
END;
$$;


CREATE FUNCTION subscription."updateSubscriptionItemCount"() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE "subscription"."subscriptionItemCount"
SET "subscriptionTitleId" = (select "subscriptionTitleId" from "subscription"."subscriptionServing" where id = NEW."subscriptionServingId")
WHERE id = NEW.id;
    RETURN null;
END;
$$;


CREATE FUNCTION subscription."updateSubscriptionOccurence"() RETURNS trigger LANGUAGE plpgsql AS $$
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


CREATE FUNCTION subscription."updateSubscriptionOccurence_customer"() RETURNS trigger LANGUAGE plpgsql AS $$
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


CREATE FUNCTION website.set_current_timestamp_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;



CREATE FUNCTION "order".ordersummary(order_row "order"."order") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    counts jsonb;
    amounts jsonb;
BEGIN
    SELECT json_object_agg(each."orderStatus", each."count") FROM (
        SELECT "orderStatus", COUNT (*) FROM "order"."order" GROUP BY "orderStatus"
    ) AS each into counts;
    SELECT json_object_agg(each."orderStatus", each."total") FROM (
        SELECT "orderStatus", SUM ("itemTotal") as total FROM "order"."order" GROUP BY "orderStatus"
    ) AS each into amounts;
	RETURN json_build_object('count', counts, 'amount', amounts);
END
$$;
CREATE FUNCTION "order".set_current_timestamp_updated_at() RETURNS trigger
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
CREATE FUNCTION "order"."subTotal"(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    amount numeric := 0;
    discount numeric := 0;
    itemTotal numeric;
    deliveryPrice numeric;
BEGIN
    SELECT "order"."itemTotal"(cart.*) into itemTotal;
    SELECT "order"."deliveryPrice"(cart.*) into deliveryPrice;
    SELECT "order".discount(cart.*) into discount;
    amount := itemTotal + deliveryPrice + cart.tip - discount;
    RETURN amount;
END
$$;
CREATE FUNCTION "order".tax(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   taxAmount numeric := 0;
   amount numeric := 0;
   tax numeric;
   isTaxIncluded boolean;
BEGIN
    SELECT "order"."isTaxIncluded"(cart.*) INTO isTaxIncluded;
    SELECT "order"."subTotal"(cart.*) into amount;
    SELECT "order"."taxPercent"(cart.*) into tax;
    IF isTaxIncluded = true THEN
        RETURN ROUND((tax * amount)/(100 + tax), 2);
    END IF;
    RETURN ROUND(amount * (tax / 100), 2);
END;
$$;
CREATE FUNCTION "order"."taxPercent"(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    taxPercent numeric := 0;
    percentage jsonb;
    subscriptionId int;
    itemCountId int;
BEGIN
    IF cart."subscriptionOccurenceId" IS NOT NULL THEN
        SELECT "subscriptionId" INTO subscriptionId FROM subscription."subscriptionOccurence" WHERE id = cart."subscriptionOccurenceId";
        SELECT "subscriptionItemCountId" INTO itemCountId FROM subscription.subscription WHERE id = subscriptionId;
        SELECT "tax" INTO taxPercent FROM subscription."subscriptionItemCount" WHERE id = itemCountId;
        RETURN taxPercent;
    ELSEIF cart."subscriptionOccurenceId" IS NULL THEN
        SELECT value FROM brands."brand_storeSetting" WHERE "brandId" = cart."brandId" AND "storeSettingId" = (SELECT id FROM brands."storeSetting" WHERE identifier = 'Tax Percentage') INTO percentage;
        RETURN (percentage->>'value')::numeric;
    ELSE
        RETURN 2.5;
    END IF;
END;
$$;
CREATE FUNCTION "order"."totalPrice"(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   totalPrice numeric;
   tax numeric;
   rate numeric;
   loyaltyPointsAmount numeric := 0;
   subTotal numeric;
   isTaxIncluded boolean;
BEGIN
    SELECT "order"."subTotal"(cart.*) INTO subTotal;
    SELECT "order".tax(cart.*) into tax;
    SELECT "order"."isTaxIncluded"(cart.*) INTO isTaxIncluded;
    IF cart."loyaltyPointsUsed" > 0 THEN
        SELECT crm."getLoyaltyPointsConversionRate"(cart."brandId") INTO rate;
        loyaltyPointsAmount := ROUND(rate * cart."loyaltyPointsUsed", 2);
    END IF;
    IF isTaxIncluded = true THEN
        totalPrice := ROUND(subTotal - COALESCE(cart."walletAmountUsed", 0) - loyaltyPointsAmount, 2);
    ELSE
        totalPrice := ROUND(subTotal - COALESCE(cart."walletAmountUsed", 0) - loyaltyPointsAmount  + tax, 2);
    END IF;
    RETURN totalPrice;
END
$$;
CREATE FUNCTION "order"."updateStatementDescriptor"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
setting jsonb;
statementDescriptor text := 'food order';
BEGIN
    IF NEW.source = 'a-la-carte' then
        SELECT "value" from "brands"."brand_storeSetting" where "brandId" = NEW."brandId" and "storeSettingId" = (select id from "brands"."storeSetting" where "identifier" = 'Statement Descriptor') into setting;
    ELSIF NEW.source = 'subscription' then
        SELECT "value" from "brands"."brand_subscriptionStoreSetting" where "brandId" = NEW."brandId" and "subscriptionStoreSettingId" = (select id from "brands"."subscriptionStoreSetting" where "identifier" = 'Statement Descriptor') into setting;
    END IF;
    UPDATE "order"."cart" SET "statementDescriptor" = setting->>'value' where id = NEW.id;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".update_inventory_sachet_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    sachet record;
BEGIN
    IF OLD."assemblyStatus" != NEW."assemblyStatus" AND NEW."assemblyStatus" = 'COMPLETED' THEN
    	FOR sachet IN SELECT * FROM "order"."orderSachet" WHERE "orderInventoryProductId" = NEW.id LOOP
        	UPDATE "order"."orderSachet" SET
            status = 'PACKED', "isLabelled" = true, "isPortioned" = true, "isAssembled" = true
            WHERE id = sachet.id;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".update_mealkit_sachet_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    sachet record;
BEGIN
    IF OLD."assemblyStatus" != NEW."assemblyStatus" AND NEW."assemblyStatus" = 'COMPLETED' THEN
    	FOR sachet IN SELECT * FROM "order"."orderSachet" WHERE "orderMealKitProductId" = NEW.id LOOP
        	UPDATE "order"."orderSachet" SET
            status = 'PACKED', "isLabelled" = true, "isPortioned" = true, "isAssembled" = true
            WHERE id = sachet.id;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".update_order_products_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    orderItem record;
    sachetItem record;
    updatedStatus text;
    oldStatus text;
BEGIN
    updatedStatus = NEW."orderStatus";
    oldStatus = OLD."orderStatus";
    IF oldStatus != 'READY_TO_ASSEMBLE' AND updatedStatus = 'READY_TO_ASSEMBLE' THEN
        FOR orderItem IN SELECT * FROM "order"."orderInventoryProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."assemblyStatus" != 'COMPLETED' THEN
                UPDATE "order"."orderInventoryProduct" SET "assemblyStatus" = 'COMPLETED' WHERE id = orderItem.id;
            END IF;
        END LOOP;
        FOR orderItem IN SELECT * FROM "order"."orderReadyToEatProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."assemblyStatus" != 'COMPLETED' THEN
                UPDATE "order"."orderReadyToEatProduct" SET "assemblyStatus" = 'COMPLETED' WHERE id = orderItem.id;
            END IF;
        END LOOP;
        FOR orderItem IN SELECT * FROM "order"."orderMealKitProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."assemblyStatus" != 'COMPLETED' THEN
                UPDATE "order"."orderMealKitProduct" SET "assemblyStatus" = 'COMPLETED' WHERE id = orderItem.id;
            END IF;
        END LOOP;
    END IF;
    IF oldStatus != 'READY_TO_DISPATCH' AND updatedStatus = 'READY_TO_DISPATCH' THEN
        FOR orderItem IN SELECT * FROM "order"."orderInventoryProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."isAssembled" = false THEN
                UPDATE "order"."orderInventoryProduct" SET "isAssembled" = true WHERE id = orderItem.id;
            END IF;
        END LOOP;
        FOR orderItem IN SELECT * FROM "order"."orderReadyToEatProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."isAssembled" = false THEN
                UPDATE "order"."orderReadyToEatProduct" SET "isAssembled" = true WHERE id = orderItem.id;
            END IF;
        END LOOP;
        FOR orderItem IN SELECT * FROM "order"."orderMealKitProduct" WHERE "orderId" = NEW.id LOOP
            IF orderItem."isAssembled" = false THEN
                UPDATE "order"."orderMealKitProduct" SET "isAssembled" = true WHERE id = orderItem.id;
            END IF;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".update_readytoeat_sachet_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    sachet record;
BEGIN
    IF OLD."assemblyStatus" != NEW."assemblyStatus" AND NEW."assemblyStatus" = 'COMPLETED' THEN
    	FOR sachet IN SELECT * FROM "order"."orderSachet" WHERE "orderReadyToEatProductId" = NEW.id LOOP
        	UPDATE "order"."orderSachet" SET
            status = 'PACKED', "isLabelled" = true, "isPortioned" = true, "isAssembled" = true
            WHERE id = sachet.id;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order"."validateFulfillmentInfo"(f jsonb, brandidparam integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    res jsonb;
    recurrence record;
    timeslot record;
    slotFrom time;
    slotUpto time;
    slotDate timestamp;
    isValid boolean;
    err text := '';
BEGIN
    IF (f->'slot'->>'from')::timestamp > NOW()::timestamp THEN
        IF f->>'type' = 'ONDEMAND_DELIVERY' THEN
            -- FOR recurrence IN SELECT * FROM fulfilment.recurrence WHERE "type" = 'ONDEMAND_DELIVERY' LOOP
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
            SELECT * FROM fulfilment."timeSlot" WHERE id = (SELECT "timeSlotId" FROM fulfilment."mileRange" WHERE id = (f->'slot'->>'mileRangeId')::int AND "isActive" = true) AND "isActive" = true INTO timeslot;
            IF timeslot."from" < CURRENT_TIME AND timeslot."to" > CURRENT_TIME THEN
                SELECT * FROM fulfilment.recurrence WHERE id = timeslot."recurrenceId" AND "isActive" = true INTO recurrence;
                IF recurrence IS NOT NULL AND recurrence.psql_rrule::_rrule.rruleset @> NOW()::TIMESTAMP WITHOUT TIME ZONE THEN
                    res := json_build_object('status', true, 'error', 'Valid date and time!');
                ELSE
                    res := json_build_object('status', false, 'error', 'Invalid date!');
                END IF;
            ELSE
                res := json_build_object('status', false, 'error', 'Invalid time!');
            END IF;      
        ELSIF f->>'type' = 'PREORDER_DELIVERY' THEN
            slotFrom := substring(f->'slot'->>'from', 12, 8)::time;
            slotUpto := substring(f->'slot'->>'to', 12, 8)::time;
            slotDate := substring(f->'slot'->>'from', 0, 11)::timestamp;
                SELECT * FROM fulfilment."timeSlot" WHERE id = (SELECT "timeSlotId" FROM fulfilment."mileRange" WHERE id = (f->'slot'->>'mileRangeId')::int AND "isActive" = true) AND "isActive" = true INTO timeslot;
                IF timeslot."from" < slotFrom AND timeslot."to" > slotFrom THEN -- lead time is already included in the slot (front-end)
                    SELECT * FROM fulfilment.recurrence WHERE id = timeslot."recurrenceId" AND "isActive" = true INTO recurrence;
                    IF recurrence IS NOT NULL AND recurrence.psql_rrule::_rrule.rruleset @> slotDate THEN
                        res := json_build_object('status', true, 'error', 'Valid date and time!');
                    ELSE
                        res := json_build_object('status', false, 'error', 'Invalid date!');
                    END IF;
                ELSE
                    res := json_build_object('status', false, 'error', 'Invalid time!');
                END IF;
        ELSIF f->>'type' = 'ONDEMAND_PICKUP' THEN
            slotFrom := substring(f->'slot'->>'from', 12, 8)::time;
            slotUpto := substring(f->'slot'->>'to', 12, 8)::time;
            slotDate := substring(f->'slot'->>'from', 0, 11)::timestamp;
            isValid := false;
            FOR recurrence IN SELECT * FROM fulfilment.recurrence WHERE "type" = 'ONDEMAND_PICKUP' AND "isActive" = true AND id IN (SELECT "recurrenceId" FROM fulfilment.brand_recurrence WHERE "brandId" = brandIdParam) LOOP
                IF recurrence.psql_rrule::_rrule.rruleset @> NOW()::TIMESTAMP WITHOUT TIME ZONE THEN
                    FOR timeslot IN SELECT * FROM fulfilment."timeSlot" WHERE "recurrenceId" = recurrence.id AND "isActive" = true LOOP
                        IF timeslot."from" < slotFrom AND timeslot."to" > slotFrom THEN 
                            isValid := true;
                            EXIT;
                        END IF;
                    END LOOP;
                    IF isValid = false THEN
                        err := 'No time slot available!';
                    END IF;
                END IF; 
            END LOOP;
            res := json_build_object('status', isValid, 'error', err);
        ELSE
            slotFrom := substring(f->'slot'->>'from', 12, 8)::time;
            slotUpto := substring(f->'slot'->>'to', 12, 8)::time;
            slotDate := substring(f->'slot'->>'from', 0, 11)::timestamp;
            isValid := false;
            FOR recurrence IN SELECT * FROM fulfilment.recurrence WHERE "type" = 'PREORDER_PICKUP' AND "isActive" = true AND id IN (SELECT "recurrenceId" FROM fulfilment.brand_recurrence WHERE "brandId" = brandIdParam) LOOP
                IF recurrence.psql_rrule::_rrule.rruleset @> slotDate THEN
                    FOR timeslot IN SELECT * FROM fulfilment."timeSlot" WHERE "recurrenceId" = recurrence.id AND "isActive" = true LOOP
                        IF timeslot."from" < slotFrom AND timeslot."to" > slotFrom THEN 
                            isValid := true;
                            EXIT;
                        END IF;
                    END LOOP;
                    IF isValid = false THEN
                        err := 'No time slot available!';
                    END IF;
                END IF; 
            END LOOP;
            res := json_build_object('status', isValid, 'error', err);
        END IF;
    ELSE
        res := jsonb_build_object('status', false, 'error', 'Slot expired!');
    END IF;
    res := res || jsonb_build_object('type', 'fulfillment');
    RETURN res;
END
$$;
CREATE FUNCTION "order"."walletAmountUsable"(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   setting record;
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
    SELECT * FROM brands."storeSetting" WHERE "identifier" = 'Loyalty Points Usage' AND "type" = 'rewards' INTO setting;
    SELECT * FROM brands."brand_storeSetting" WHERE "storeSettingId" = setting.id AND "brandId" = cart."brandId" INTO temp;
    IF temp IS NOT NULL THEN
        setting := temp;
    END IF;
    SELECT "order"."itemTotal"(cart.*) into itemTotal;
    SELECT "order"."deliveryPrice"(cart.*) into deliveryPrice;
    SELECT "order".tax(cart.*) into tax;
    SELECT "order".discount(cart.*) into discount;
    totalPrice := ROUND(itemTotal + deliveryPrice + cart.tip  + tax - discount, 2);
    amountUsable := totalPrice;
    -- if loyalty points are used
    IF cart."loyaltyPointsUsed" > 0 THEN
        SELECT crm."getLoyaltyPointsConversionRate"(cart."brandId") INTO rate;
        pointsAmount := rate * cart."loyaltyPointsUsed";
        amountUsable := amountUsable - pointsAmount;
    END IF;
    SELECT amount FROM crm."wallet" WHERE "keycloakId" = cart."customerKeycloakId" AND "brandId" = cart."brandId" INTO balance;
    IF amountUsable > balance THEN
        amountUsable := balance;
    END IF;
    -- if usable changes after cart update, then update used amount
    IF cart."walletAmountUsed" > amountUsable THEN
        PERFORM crm."setWalletAmountUsedInCart"(cart.id, amountUsable);
    END IF;
    RETURN amountUsable;
END;
$$;

CREATE FUNCTION products."comboProductComponentBasePrice"(component products."comboProductComponent") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    basePrice jsonb;
BEGIN
    IF component.options IS NULL THEN
        IF component."inventoryProductId" IS NOT NULL THEN
            basePrice := jsonb_build_object('price', 0, 'discount', 0);
        ELSIF component."simpleRecipeProductId" IS NOT NULL THEN
            basePrice := jsonb_build_object('price', 0, 'discount', 0);
        ELSE
            basePrice := jsonb_build_object('price', 0, 'discount', 0);
        END IF;
    ELSE
        basePrice := jsonb_build_object('price', (component.options->0->>'price')::numeric, 'discount', (component.options->0->>'discount')::numeric);
    END IF;
    RETURN basePrice;
END;
$$;

CREATE FUNCTION "order"."addOnTotal"(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   total numeric := 0;
   product "order"."cartItem";
BEGIN
    IF cart."source" = 'a-la-carte' THEN
        RETURN 0;
    ELSE
        FOR product IN SELECT * FROM "order"."cartItem" WHERE "cartId" = cart.id LOOP
            total := total + COALESCE(product."addOnPrice", 0);
            IF product."isAddOn" = true THEN
                total := total + product."unitPrice";
            END IF;
        END LOOP;
        RETURN total;
    END IF;
END
$$;


CREATE FUNCTION "order"."createSachets"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    inventorySachet "products"."inventoryProductBundleSachet";
    sachet "simpleRecipe"."simpleRecipeYield_ingredientSachet";
    counter int;
    modifierOption record;
BEGIN
    IF NEW."simpleRecipeYieldId" IS NOT NULL THEN
        FOR sachet IN SELECT * FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = NEW."simpleRecipeYieldId" LOOP
            IF sachet."ingredientSachetId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","ingredientSachetId","cartId") VALUES (NEW.id, sachet."ingredientSachetId", NEW."cartId");
            ELSEIF sachet."subRecipeYieldId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","subRecipeYieldId","cartId") VALUES (NEW.id, sachet."subRecipeYieldId", NEW."cartId");
            END IF;
        END LOOP;
    ELSEIF NEW."inventoryProductBundleId" IS NOT NULL THEN
        FOR inventorySachet IN SELECT * FROM "products"."inventoryProductBundleSachet" WHERE "inventoryProductBundleId" = NEW."inventoryProductBundleId" LOOP
            IF inventorySachet."sachetItemId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","sachetItemId", "cartId") VALUES (NEW.id, inventorySachet."sachetItemId", NEW."cartId");
            END IF;
        END LOOP;
    ELSEIF NEW."subRecipeYieldId" IS NOT NULL THEN
        FOR sachet IN SELECT * FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = NEW."subRecipeYieldId" LOOP
            IF sachet."ingredientSachetId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","ingredientSachetId","cartId") VALUES (NEW.id, sachet."ingredientSachetId", NEW."cartId");
            ELSEIF sachet."subRecipeYieldId" IS NOT NULL THEN
                INSERT INTO "order"."cartItem"("parentCartItemId","subRecipeYieldId","cartId") VALUES (NEW.id, sachet."subRecipeYieldId", NEW."cartId");
            END IF;
        END LOOP;
    ELSEIF NEW."modifierOptionId" IS NOT NULL THEN
        SELECT * FROM "onDemand"."modifierCategoryOption" WHERE id = NEW."modifierOptionId" INTO modifierOption;
        counter := modifierOption.quantity;
        IF modifierOption."sachetItemId" IS NOT NULL THEN 
            WHILE counter >= 1 LOOP
                INSERT INTO "order"."cartItem"("parentCartItemId","sachetItemId","cartId") VALUES (NEW.id,  modifierOption."sachetItemId", NEW."cartId");
                counter := counter - 1;
            END LOOP;
        ELSEIF modifierOption."simpleRecipeYieldId" IS NOT NULL THEN
            WHILE counter >= 1 LOOP
                 INSERT INTO "order"."cartItem"("parentCartItemId","subRecipeYieldId","cartId") VALUES (NEW.id,  modifierOption."simpleRecipeYieldId", NEW."cartId");
                counter := counter - 1;
            END LOOP;
        ELSEIF modifierOption."ingredientSachetId" IS NOT NULL THEN
            WHILE counter >= 1 LOOP
                 INSERT INTO "order"."cartItem"("parentCartItemId","ingredientSachetId","cartId") VALUES (NEW.id,  modifierOption."ingredientSachetId", NEW."cartId");
                counter := counter - 1;
            END LOOP;
        END IF;
    END IF;
    RETURN null;
END;
$$;
CREATE FUNCTION "order"."handleProductOption"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    cart "order"."cart";
    productOption products."productOption";
    mode text;
    validFor text;
    counter int := 0;
    sachet "simpleRecipe"."simpleRecipeYield_ingredientSachet";
BEGIN
    IF NEW."productOptionId" IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT * from "order"."cart" WHERE id = NEW.cartId INTO cart;
    IF cart."paymentStatus" = 'SUCCEEDED' THEN
        SELECT * INTO productOption FROM products."productOption" WHERE id = NEW."productOptionId";
        SELECT "orderMode" INTO mode FROM products."productOptionType" WHERE title = productOption."type";
        SELECT "validWhen" INTO validFor FROM "order"."orderMode" WHERE title = mode;
        IF validFor = 'recipe' THEN
            counter := productOption.quantity;
            WHILE counter >= 1 LOOP
                INSERT INTO "order"."cartItem"("parentCartItemId","simpleRecipeYieldId") VALUES (NEW.id, productOption."simpleRecipeYieldId") RETURNING id;
                FOR sachet IN SELECT * FROM "simpleRecipe"."simpleRecipeYield_ingredientSachet" WHERE "recipeYieldId" = productOption."simpleRecipeYieldId" LOOP
                    INSERT INTO "order"."cartItem"("parentCartItemId","ingredientSachetId") VALUES (id, sachet."ingredientSachetId");
                END LOOP;
                counter := counter - 1;
            END LOOP;
        ELSIF validFor = 'sachetItem' THEN
            counter := productOption.quantity;
            WHILE counter >= 1 LOOP
                INSERT INTO "order"."cartItem"("parentCartItemId","sachetItemId") VALUES (NEW.id, productOption."sachetItemId") RETURNING id;
                counter := counter - 1;
            END LOOP;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;


CREATE FUNCTION "order"."deliveryPrice"(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    value numeric;
    total numeric;
    rangeId int;
    subscriptionId int;
    price numeric:=0;
BEGIN
    IF cart."fulfillmentInfo"::json->>'type' LIKE '%PICKUP' OR cart."fulfillmentInfo" IS NULL
        THEN RETURN 0;
    END IF;
    IF cart."source" = 'a-la-carte' THEN
        SELECT "order"."itemTotal"(cart) into total;
        SELECT cart."fulfillmentInfo"::json#>'{"slot","mileRangeId"}' as int into rangeId;
        SELECT charge from "fulfilment"."charge" WHERE charge."mileRangeId" = rangeId AND total >= charge."orderValueFrom" AND total < charge."orderValueUpto" into value;
        IF value IS NOT NULL
            THEN RETURN value;
        END IF;
        SELECT MAX(charge) from "fulfilment"."charge" WHERE charge."mileRangeId" = rangeId into value;
        IF value IS NULL
            THEN RETURN 0;
        ELSE 
            RETURN value;
        END IF;
    ELSE
        SELECT "subscriptionId" 
        FROM crm."brand_customer" 
        WHERE "brandId" = cart."brandId" 
        AND "keycloakId" = cart."customerKeycloakId" 
        INTO subscriptionId;
        SELECT "deliveryPrice" 
        FROM subscription."subscription_zipcode" 
        WHERE "subscriptionId" = subscriptionId 
        AND zipcode = cart.address->>'zipcode'
        INTO price;
        RETURN COALESCE(price, 0);
    END IF;
    RETURN 0;
END
$$;
CREATE FUNCTION "order".discount(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   totalPrice numeric;
   itemTotal numeric;
   deliveryPrice numeric;
   rewardIds int[];
   rewardId int;
   reward record;
   discount numeric := 0;
BEGIN
    SELECT "order"."itemTotal"(cart.*) into itemTotal;
    SELECT "order"."deliveryPrice"(cart.*) into deliveryPrice;
    totalPrice := ROUND(itemTotal + deliveryPrice, 2);
    rewardIds := ARRAY(SELECT "rewardId" FROM "order"."cart_rewards" WHERE "cartId" = cart.id);
    FOREACH rewardId IN ARRAY rewardIds LOOP
        SELECT * FROM crm.reward WHERE id = rewardId INTO reward;
        IF reward."type" = 'Discount'
            THEN
            IF  reward."rewardValue"->>'type' = 'conditional'
                THEN 
                discount := totalPrice * ((reward."rewardValue"->'value'->>'percentage')::numeric / 100);
                IF discount >  (reward."rewardValue"->'value'->>'max')::numeric
                    THEN discount := (reward."rewardValue"->'value'->>'max')::numeric;
                END IF;
            ELSIF reward."rewardValue"->>'type' = 'absolute' THEN
                discount := (reward."rewardValue"->>'value')::numeric;
            ELSE
                discount := 0;
            END IF;
        END IF;
    END LOOP;
    IF discount > totalPrice THEN
        discount := totalPrice;
    END IF;
    RETURN ROUND(discount, 2);
END;
$$;
CREATE FUNCTION "order"."duplicateCartItem"(params jsonb) RETURNS SETOF public.response
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM "order"."duplicateCartItemVolatile"(params);
    RETURN QUERY SELECT true AS success, 'Item duplicated!' AS message;
END;
$$;
CREATE FUNCTION "order"."duplicateCartItemVolatile"(params jsonb) RETURNS SETOF void
    LANGUAGE plpgsql
    AS $$
DECLARE
    currentItem record;
    item record;
    parentCartItemId int;
BEGIN
    SELECT * FROM "order"."cartItem" WHERE id = (params->>'cartItemId')::int INTO item;
    INSERT INTO "order"."cartItem"("cartId", "parentCartItemId", "isModifier", "productId", "productOptionId", "comboProductComponentId", "customizableProductComponentId", "simpleRecipeYieldId", "sachetItemId", "unitPrice", "ingredientSachetId", "isAddOn", "addOnPrice", "inventoryProductBundleId", "modifierOptionId", "subRecipeYieldId") 
    VALUES(item."cartId", (params->>'parentCartItemId')::int, item."isModifier", item."productId", item."productOptionId", item."comboProductComponentId", item."customizableProductComponentId", item."simpleRecipeYieldId", item."sachetItemId", item."unitPrice", item."ingredientSachetId", item."isAddOn", item."addOnPrice", item."inventoryProductBundleId", item."modifierOptionId", item."subRecipeYieldId")
    RETURNING id INTO parentCartItemId;
    FOR currentItem IN SELECT * FROM "order"."cartItem" WHERE "parentCartItemId" = item.id LOOP
        IF currentItem."ingredientSachetId" IS NULL AND currentItem."sachetItemId" IS NULL AND currentItem."subRecipeYieldId" IS NULL THEN
            PERFORM "order"."duplicateCartItemVolatile"(jsonb_build_object('cartItemId', currentItem.id, 'parentCartItemId', parentCartItemId));
        END IF;
    END LOOP;
END;
$$;

CREATE FUNCTION "order"."isCartValid"(cart "order".cart) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    totalPrice numeric := 0;
    res jsonb;
    productsCount int := 0;
BEGIN
    SELECT "order"."totalPrice"(cart.*) INTO totalPrice;
    SELECT count(*) INTO productsCount FROM "order"."cartItem" WHERE "cartId" = cart.id;
    IF productsCount = 0
        THEN res := json_build_object('status', false, 'error', 'No items in cart!');
    ELSIF cart."customerInfo" IS NULL OR cart."customerInfo"->>'customerFirstName' IS NULL 
        THEN res := json_build_object('status', false, 'error', 'Basic customer details missing!');
    ELSIF cart."fulfillmentInfo" IS NULL
        THEN res := json_build_object('status', false, 'error', 'No fulfillment mode selected!');
    ELSIF cart."fulfillmentInfo" IS NOT NULL AND cart.status = 'PENDING'
        THEN SELECT "order"."validateFulfillmentInfo"(cart."fulfillmentInfo", cart."brandId") INTO res;
        IF (res->>'status')::boolean = false THEN
            PERFORM "order"."clearFulfillmentInfo"(cart.id);
        END IF;
    ELSIF cart."address" IS NULL AND cart."fulfillmentInfo"::json->>'type' LIKE '%DELIVERY' 
        THEN res := json_build_object('status', false, 'error', 'No address selected for delivery!');
    ELSIF totalPrice > 0 AND totalPrice <= 0.5
        THEN res := json_build_object('status', false, 'error', 'Transaction amount should be greater than $0.5!');
    ELSE
        res := jsonb_build_object('status', true, 'error', '');
    END IF;
    RETURN res;
END
$_$;
CREATE FUNCTION "order"."isTaxIncluded"(cart "order".cart) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    subscriptionId int;
    itemCountId int;
    taxIncluded boolean;
BEGIN
    IF cart."subscriptionOccurenceId" IS NOT NULL THEN
        SELECT "subscriptionId" INTO subscriptionId FROM subscription."subscriptionOccurence" WHERE id = cart."subscriptionOccurenceId";
        SELECT "subscriptionItemCountId" INTO itemCountId FROM subscription.subscription WHERE id = subscriptionId;
        SELECT "isTaxIncluded" INTO taxIncluded FROM subscription."subscriptionItemCount" WHERE id = itemCountId;
        RETURN taxIncluded;
    END IF;
    RETURN false;
END;
$$;
CREATE FUNCTION "order"."itemTotal"(cart "order".cart) RETURNS numeric
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   total numeric;
BEGIN
    SELECT SUM("unitPrice") INTO total FROM "order"."cartItem" WHERE "cartId" = cart."id";
    RETURN COALESCE(total, 0);
END;
$$;
CREATE FUNCTION "order"."loyaltyPointsUsable"(cart "order".cart) RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
   setting record;
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
    SELECT * FROM brands."storeSetting" WHERE "identifier" = 'Loyalty Points Usage' AND "type" = 'rewards' INTO setting;
    SELECT * FROM brands."brand_storeSetting" WHERE "storeSettingId" = setting.id AND "brandId" = cart."brandId" INTO temp;
    IF temp IS NOT NULL THEN
        setting := temp;
    END IF;
    IF setting IS NULL THEN
        RETURN pointsUsable;
    END IF;
    SELECT "order"."itemTotal"(cart.*) into itemTotal;
    SELECT "order"."deliveryPrice"(cart.*) into deliveryPrice;
    SELECT "order".tax(cart.*) into tax;
    SELECT "order".discount(cart.*) into discount;
    totalPrice := ROUND(itemTotal + deliveryPrice + cart.tip  + tax - cart."walletAmountUsed" - discount, 2);
    amount := ROUND(totalPrice * ((setting.value->>'percentage')::float / 100));
    IF amount > (setting.value->>'max')::int THEN
        amount := (setting.value->>'max')::int;
    END IF;
    SELECT crm."getLoyaltyPointsConversionRate"(cart."brandId") INTO rate;
    pointsUsable = ROUND(amount / rate);
    SELECT points FROM crm."loyaltyPoint" WHERE "keycloakId" = cart."customerKeycloakId" AND "brandId" = cart."brandId" INTO balance;
    IF pointsUsable > balance THEN
        pointsUsable := balance;
    END IF;
    -- if usable changes after cart update, then update used points
    IF cart."loyaltyPointsUsed" > pointsUsable THEN
        PERFORM crm."setLoyaltyPointsUsedInCart"(cart.id, pointsUsable);
    END IF;
    RETURN pointsUsable;
END;
$$;
CREATE FUNCTION "order"."onPaymentSuccess"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    cart "order"."cart";
    tax numeric := 0;
    itemTotal numeric := 0;
    deliveryPrice numeric := 0;
    totalPrice numeric := 0;
BEGIN
    IF (SELECT COUNT(*) FROM "order"."order" WHERE "cartId" = NEW."id") > 0 THEN
        RETURN NULL;
    END IF;
    IF NEW."paymentStatus" != 'PENDING' THEN
        SELECT * from "order"."cart" WHERE id = NEW.id INTO cart;
        SELECT "order"."itemTotal"(cart.*) INTO itemTotal;
        SELECT "order"."tax"(cart.*) INTO tax;
        SELECT "order"."deliveryPrice"(cart.*) INTO deliveryPrice;
        SELECT "order"."totalPrice"(cart.*) INTO totalPrice;
        INSERT INTO "order"."order"("cartId", "tip", "tax","itemTotal","deliveryPrice", "fulfillmentType","amountPaid", "keycloakId", "brandId")
            VALUES (NEW.id, NEW.tip,tax, itemTotal,deliveryPrice, NEW."fulfillmentInfo"->>'type',totalPrice, NEW."customerKeycloakId", NEW."brandId");
        UPDATE "order"."cart" 
            SET 
                "orderId" = (SELECT id FROM "order"."order" WHERE "cartId" = NEW.id),
                status = 'ORDER_PENDING'
        WHERE id = NEW.id;
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".on_cart_item_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    totalReady integer := 0;
    totalPacked integer := 0;
    totalItems integer := 0;
BEGIN
    IF NEW.status = OLD.status THEN
        RETURN NULL;
    END IF;
    -- mark children packed if parent ready/packed
    IF NEW.status = 'READY' OR NEW.status = 'PACKED' THEN
        UPDATE "order"."cartItem" SET status = 'PACKED' WHERE "parentCartItemId" = NEW.id;
    END IF;
    IF NEW.status = 'READY_FOR_PACKING' OR NEW.status = 'READY' THEN
        IF NEW."parentCartItemId" IS NULL THEN
            UPDATE "order"."cartItem" SET status = 'PACKED' WHERE id = NEW.id; -- product
        ELSEIF (SELECT "parentCartItemId" FROM "order"."cartItem" WHERE id = NEW."parentCartItemId") IS NULL THEN
            UPDATE "order"."cartItem" SET status = 'PACKED' WHERE id = NEW.id; -- productComponent
        END IF;
    END IF;
    IF NEW.status = 'READY' THEN
        SELECT COUNT(*) INTO totalReady FROM "order"."cartItem" WHERE "parentCartItemId" = NEW."parentCartItemId" AND status = 'READY';
        SELECT COUNT(*) INTO totalItems FROM "order"."cartItem" WHERE "parentCartItemId" = NEW."parentCartItemId";
        IF totalReady = totalItems THEN
            UPDATE "order"."cartItem" SET status = 'READY_FOR_PACKING' WHERE id = NEW."parentCartItemId";
        END IF;
    END IF;
    IF NEW.status = 'PACKED' THEN
        SELECT COUNT(*) INTO totalPacked FROM "order"."cartItem" WHERE "parentCartItemId" = NEW."parentCartItemId" AND status = 'PACKED';
        SELECT COUNT(*) INTO totalItems FROM "order"."cartItem" WHERE "parentCartItemId" = NEW."parentCartItemId";
        IF totalPacked = totalItems THEN
            UPDATE "order"."cartItem" SET status = 'READY' WHERE id = NEW."parentCartItemId" AND status = 'PENDING';
        END IF;
    END IF;
    -- check order item status
    IF (SELECT status FROM "order".cart WHERE id = NEW."cartId") = 'ORDER_PENDING' THEN
        UPDATE "order".cart SET status = 'ORDER_UNDER_PROCESSING' WHERE id = NEW."cartId";
    END IF;
    IF NEW."parentCartItemId" IS NOT NULL THEN
        RETURN NULL;
    END IF;
    SELECT COUNT(*) INTO totalReady FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW."cartId" AND status = 'READY';
    SELECT COUNT(*) INTO totalPacked FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW."cartId" AND status = 'PACKED';
    SELECT COUNT(*) INTO totalItems FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW."cartId";
    IF totalReady = totalItems THEN
        UPDATE "order".cart SET status = 'ORDER_READY_TO_ASSEMBLE' WHERE id = NEW."cartId";
    ELSEIF totalPacked = totalItems THEN
        UPDATE "order".cart SET status = 'ORDER_READY_TO_DISPATCH' WHERE id = NEW."cartId";
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".on_cart_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    item "order"."cartItem";
    packedCount integer := 0;
    readyCount integer := 0;
BEGIN
    IF OLD.status = NEW.status THEN
        RETURN NULL;
    END IF;
    IF NEW.status = 'ORDER_READY_TO_ASSEMBLE' THEN
        FOR item IN SELECT * FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW.id LOOP
            UPDATE "order"."cartItem" SET status = 'READY' WHERE id = item.id;
        END LOOP;
    ELSEIF NEW.status = 'ORDER_READY_FOR_DISPATCH' THEN
        FOR item IN SELECT * FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW.id LOOP
            UPDATE "order"."cartItem" SET status = 'PACKED' WHERE id = item.id;
        END LOOP;
    ELSEIF NEW.status = 'ORDER_OUT_FOR_DELIVERY' OR NEW.status = 'ORDER_DELIVERED' THEN
        FOR item IN SELECT * FROM "order"."cartItem" WHERE "parentCartItemId" IS NULL AND "cartId" = NEW.id LOOP
            UPDATE "order"."cartItem" SET status = 'PACKED' WHERE id = item.id;
        END LOOP;
    END IF;
    RETURN NULL;
END;
$$;



CREATE FUNCTION products."comboProductComponentCustomizableCartItem"(componentoption products."customizableComponentOptions") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
    product record;
    option record;
BEGIN
    SELECT * FROM products.product WHERE id = componentOption."productId" INTO product;
    SELECT * FROM products."productOption" WHERE id = componentOption."productOptionId" INTO option;
    counter := option.quantity;
    IF option."simpleRecipeYieldId" IS NOT NULL THEN 
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    RETURN jsonb_build_object(
        'customizableProductComponentId', componentOption."customizableComponentId",
        'productOptionId', componentOption."productOptionId",
        'unitPrice', componentOption.price,
        'childs', json_build_object(
            'data', items
        )
    );
END;
$$;

CREATE FUNCTION products."comboProductComponentOptionCartItem"(componentoption products."comboComponentOptions") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
    product record;
    option record;
BEGIN
    SELECT * FROM products.product WHERE id = componentOption."productId" INTO product;
    SELECT * FROM products."productOption" WHERE id = componentOption."productOptionId" INTO option;
    counter := option.quantity;
    IF option."simpleRecipeYieldId" IS NOT NULL THEN 
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    RETURN jsonb_build_object(
        'comboProductComponentId', componentOption."comboComponentId",
        'productOptionId', componentOption."productOptionId",
        'unitPrice', componentOption.price,
        'childs', json_build_object(
            'data', items
        )
    );
END;
$$;


CREATE FUNCTION products."customizableProductComponentOptionCartItem"(componentoption products."customizableComponentOptions") RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
    product record;
    option record;
BEGIN
    SELECT * FROM products.product WHERE id = componentOption."productId" INTO product;
    SELECT * FROM products."productOption" WHERE id = componentOption."productOptionId" INTO option;
    counter := option.quantity;
    IF option."simpleRecipeYieldId" IS NOT NULL THEN 
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    RETURN jsonb_build_object(
            'productId', product.id,
            'unitPrice', product.price,
            'childs', jsonb_build_object(
                'data', json_build_array(
                    json_build_object (
                        'customizableProductComponentId', componentOption."customizableComponentId",
                        'productOptionId', componentOption."productOptionId",
                        'unitPrice', componentOption.price,
                        'childs', json_build_object(
                            'data', items
                        )
                    )
                )
            )
        );
END;
$$;


CREATE FUNCTION products."getProductType"(pid integer) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    productOption record;
    comboComponentsCount int;
    customizableOptionsCount int;
BEGIN
    SELECT * FROM products."productOption" WHERE id = pId INTO productOption LIMIT 1;
    SELECT COUNT(*) FROM products."customizableProductOption" WHERE "productId" = pId INTO customizableOptionsCount;
    SELECT COUNT(*) FROM products."comboProductComponent" WHERE "productId" = pId INTO comboComponentsCount;
    IF productOption."sachetItemId" IS NOT NULL OR productOption."supplierItemId" IS NOT NULL THEN
        RETURN 'inventoryProduct';
    ELSIF productOption."simpleRecipeYieldId" IS NOT NULL THEN
        RETURN 'simpleRecipeProduct';
    ELSEIF customizableOptionsCount > 0 THEN
        RETURN 'customizableProduct';
    ELSEIF comboComponentsCount > 0 THEN
        RETURN 'comboProduct';
    ELSE
        RETURN 'none';
    END IF;
END;
$$;

CREATE FUNCTION products."productCartItemById"(optionid integer) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    counter int;
    items jsonb[] := '{}';
    option products."productOption";
    product products."product";
BEGIN
    SELECT * INTO option FROM products."productOption" WHERE id = optionId;
    SELECT * FROM products.product WHERE id = option."productId" INTO product;
    counter := option.quantity;
    IF option."simpleRecipeYieldId" IS NOT NULL THEN 
        WHILE counter >= 1 LOOP
            items := items || json_build_object('simpleRecipeYieldId', option."simpleRecipeYieldId")::jsonb;
            counter := counter - 1;
        END LOOP;
    ELSEIF option."inventoryProductBundleId" IS NOT NULL THEN
        WHILE counter >= 1 LOOP
            items := items || json_build_object('inventoryProductBundleId', option."inventoryProductBundleId")::jsonb;
            counter := counter - 1;
        END LOOP;
    END IF;
    RETURN json_build_object(
        'productId', product.id,
        'childs', jsonb_build_object(
            'data', json_build_array(
                json_build_object (
                    'productOptionId', option.id,
                    'unitPrice', 0,
                    'childs', json_build_object(
                        'data', items
                    )
                )
            )
        )
    );
END
$$;

CREATE FUNCTION "order"."cartBillingDetails"(cart "order".cart) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    item jsonb := '{}';
    itemTotal numeric;
    addOnTotal numeric;
    deliveryPrice numeric;
    subTotal numeric;
    tax numeric;
    taxPercent numeric;
    isTaxIncluded boolean;
    discount numeric;
    totalPrice numeric;
BEGIN
    SELECT "order"."isTaxIncluded"(cart.*) INTO isTaxIncluded;
    SELECT "order"."itemTotal"(cart.*) INTO itemTotal;
    SELECT "order"."addOnTotal"(cart.*) INTO addOnTotal;
    SELECT "order"."deliveryPrice"(cart.*) INTO deliveryPrice; 
    SELECT "order"."discount"(cart.*) INTO discount; 
    SELECT "order"."subTotal"(cart.*) INTO subTotal;
    SELECT "order".tax(cart.*) INTO tax;
    SELECT "order"."taxPercent"(cart.*) INTO taxPercent;
    SELECT "order"."totalPrice"(cart.*) INTO totalPrice;
    item:=item || jsonb_build_object('isTaxIncluded', isTaxIncluded);
    item:=item || jsonb_build_object('discount', jsonb_build_object('value', discount, 'label', 'Discount'));
    item:=item || jsonb_build_object('loyaltyPointsUsed', jsonb_build_object('value', cart."loyaltyPointsUsed", 'label', 'Loyalty Points'));
    item:=item || jsonb_build_object('walletAmountUsed', jsonb_build_object('value', cart."walletAmountUsed", 'label', 'Wallet Amount'));
    item:=item || jsonb_build_object('itemTotal', jsonb_build_object('value', itemTotal, 'description', 'Includes your base price and add on price.', 'label','Item Total', 'comment', CONCAT('Includes add on total of ', '{{',COALESCE(addOnTotal,0),'}}')));
    item:=item || jsonb_build_object('deliveryPrice', jsonb_build_object('value', deliveryPrice, 'description', '', 'label','Delivery Fee', 'comment', ''));
    IF isTaxIncluded = false THEN
        item:=item || jsonb_build_object('subTotal', jsonb_build_object('value', subTotal, 'description', '', 'label','Sub Total', 'comment', ''));
        item:=item || jsonb_build_object('tax', jsonb_build_object('value', tax, 'description', '', 'label','Tax', 'comment', CONCAT('Your tax is calculated at ', taxPercent,'%')));
        item:=item || jsonb_build_object('totalPrice', jsonb_build_object('value', totalPrice, 'description', '', 'label','Total Price', 'comment', ''));
    ELSE
        item:=item || jsonb_build_object('totalPrice', jsonb_build_object('value', totalPrice, 'description', '', 'label','Total Price', 'comment', CONCAT('Tax inclusive of ', '{{',tax,'}}', ' at ', taxPercent, '%')));
    END IF;
    RETURN item;
END
$$;
CREATE FUNCTION "order".check_main_order_status_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    productOrder record;
    assemblyStatusPendingCount numeric = 0;
    isAssembledFalseCount numeric = 0;
BEGIN
    FOR productOrder IN SELECT * FROM "order"."orderMealKitProduct" WHERE "orderId" = NEW."orderId" LOOP
        IF productOrder."assemblyStatus" != 'COMPLETED' THEN
            assemblyStatusPendingCount = assemblyStatusPendingCount + 1;
        END IF;
        IF productOrder."isAssembled" = false THEN
            isAssembledFalseCount = isAssembledFalseCount + 1;
        END IF;
    END LOOP;
    FOR productOrder IN SELECT * FROM "order"."orderInventoryProduct" WHERE "orderId" = NEW."orderId" LOOP
        IF productOrder."assemblyStatus" != 'COMPLETED' THEN
            assemblyStatusPendingCount = assemblyStatusPendingCount + 1;
        END IF;
        IF productOrder."isAssembled" = false THEN
            isAssembledFalseCount = isAssembledFalseCount + 1;
        END IF;
    END LOOP;
    FOR productOrder IN SELECT * FROM "order"."orderReadyToEatProduct" WHERE "orderId" = NEW."orderId" LOOP
        IF productOrder."assemblyStatus" != 'COMPLETED' THEN
            assemblyStatusPendingCount = assemblyStatusPendingCount + 1;
        END IF;
        IF productOrder."isAssembled" = false THEN
            isAssembledFalseCount = isAssembledFalseCount + 1;
        END IF;
    END LOOP;
    IF assemblyStatusPendingCount > 0 THEN
        UPDATE "order"."order"
        SET "orderStatus" = 'UNDER_PROCESSING'
        WHERE id = NEW."orderId";
    ELSIF ((assemblyStatusPendingCount = 0) AND (isAssembledFalseCount > 0)) THEN
        UPDATE "order"."order"
        SET "orderStatus" = 'READY_TO_ASSEMBLE'
        WHERE id = NEW."orderId";
    ELSIF ((assemblyStatusPendingCount = 0) AND (isAssembledFalseCount = 0)) THEN
        UPDATE "order"."order"
        SET "orderStatus" = 'READY_TO_DISPATCH'
        WHERE id = NEW."orderId";
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order".check_order_status_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    type text;
    sachetItem record;
    packedCount numeric = 0;
    pendingCount numeric = 0;
    assemblePending numeric = 0;
    assembleDone numeric = 0;
BEGIN
    IF NEW."orderMealKitProductId" IS NOT NULL THEN
        FOR sachetItem IN SELECT * FROM "order"."orderSachet" WHERE "orderMealKitProductId" = NEW."orderMealKitProductId" LOOP
            IF sachetItem.status = 'PENDING' THEN
                pendingCount = pendingCount + 1;
            ELSE
                packedCount = packedCount + 1;
            END IF;
            IF sachetItem."isAssembled" = false THEN
                assemblePending = assemblePending + 1;
            ELSE
                assembleDone = assembleDone + 1;
            END IF;
        END LOOP;
        IF pendingCount > 0 THEN
            UPDATE "order"."orderMealKitProduct"
            SET "assemblyStatus" = 'PENDING'
            WHERE id = NEW."orderMealKitProductId";
        ELSIF ((pendingCount = 0) AND (assemblePending > 0)) THEN
            UPDATE "order"."orderMealKitProduct"
            SET "assemblyStatus" = 'READY'
            WHERE id = NEW."orderMealKitProductId";
        ELSIF ((pendingCount = 0) AND (assemblePending = 0)) THEN
            UPDATE "order"."orderMealKitProduct"
            SET "assemblyStatus" = 'COMPLETED'
            WHERE id = NEW."orderMealKitProductId";
        END IF;
    ELSIF  NEW."orderReadyToEatProductId" IS NOT NULL THEN
        FOR sachetItem IN SELECT * FROM "order"."orderSachet" WHERE "orderReadyToEatProductId" = NEW."orderReadyToEatProductId" LOOP
            IF sachetItem.status = 'PENDING' THEN
                pendingCount = pendingCount + 1;
            ELSE
                packedCount = packedCount + 1;
            END IF;
            IF sachetItem."isAssembled" = false THEN
                assemblePending = assemblePending + 1;
            ELSE
                assembleDone = assembleDone + 1;
            END IF;
        END LOOP;
        IF pendingCount > 0 THEN
            UPDATE "order"."orderReadyToEatProduct"
            SET "assemblyStatus" = 'PENDING'
            WHERE id = NEW."orderReadyToEatProductId";
        ELSIF ((pendingCount = 0) AND (assemblePending > 0)) THEN
            UPDATE "order"."orderReadyToEatProduct"
            SET "assemblyStatus" = 'READY'
            WHERE id = NEW."orderReadyToEatProductId";
        ELSIF ((pendingCount = 0) AND (assemblePending = 0)) THEN
            UPDATE "order"."orderMealKitProduct"
            SET "assemblyStatus" = 'COMPLETED'
            WHERE id = NEW."orderReadyToEatProductId";
        END IF;
    ELSIF  NEW."orderInventoryProductId" IS NOT NULL THEN
        FOR sachetItem IN SELECT * FROM "order"."orderSachet" WHERE "orderInventoryProductId" = NEW."orderInventoryProductId" LOOP
            IF sachetItem.status = 'PENDING' THEN
                pendingCount = pendingCount + 1;
            ELSE
                packedCount = packedCount + 1;
            END IF;
            IF sachetItem."isAssembled" = false THEN
                assemblePending = assemblePending + 1;
            ELSE
                assembleDone = assembleDone + 1;
            END IF;
        END LOOP;
        IF pendingCount > 0 THEN
            UPDATE "order"."orderInventoryProduct"
            SET "assemblyStatus" = 'PENDING'
            WHERE id = NEW."orderInventoryProductId";
        ELSIF ((pendingCount = 0) AND (assemblePending > 0)) THEN
            UPDATE "order"."orderInventoryProduct"
            SET "assemblyStatus" = 'READY'
            WHERE id = NEW."orderInventoryProductId";
        ELSIF ((pendingCount = 0) AND (assemblePending = 0)) THEN
            UPDATE "order"."orderInventoryProduct"
            SET "assemblyStatus" = 'COMPLETED'
            WHERE id = NEW."orderInventoryProductId";
        END IF;
    END IF;
    RETURN NULL;
END;
$$;
CREATE FUNCTION "order"."clearFulfillmentInfo"(cartid integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE "order"."cart"
    SET "fulfillmentInfo" = NULL
    WHERE id = cartId;
END
$$;
