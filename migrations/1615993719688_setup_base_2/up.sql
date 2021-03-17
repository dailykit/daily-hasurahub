CREATE OR REPLACE FUNCTION "order".on_cart_item_status_change() RETURNS trigger LANGUAGE plpgsql AS $function$
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
$function$;

CREATE TRIGGER "on_cart_item_status_change" AFTER
UPDATE of status ON "order"."cartItem"
FOR EACH ROW EXECUTE procedure "order".on_cart_item_status_change();
CREATE OR REPLACE FUNCTION "order".on_cart_status_change() RETURNS trigger LANGUAGE plpgsql AS $function$
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
$function$;

CREATE TRIGGER "on_cart_status_change" AFTER
UPDATE of status ON "order"."cart"
FOR EACH ROW EXECUTE procedure "order".on_cart_status_change();
CREATE TRIGGER "set_order_orderCartItem_updated_at"
BEFORE
UPDATE ON "order"."cartItem"
FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_order_orderCartItem_updated_at" ON "order"."cartItem" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_order_orderCart_updated_at"
BEFORE
UPDATE ON "order".cart
FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_order_orderCart_updated_at" ON "order".cart IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_order_order_updated_at
BEFORE
UPDATE ON "order"."order"
FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_order_order_updated_at ON "order"."order" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_products_comboProductComponent_updated_at"
BEFORE
UPDATE ON products."comboProductComponent"
FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_products_comboProductComponent_updated_at" ON products."comboProductComponent" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_products_customizableProductOption_updated_at"
BEFORE
UPDATE ON products."customizableProductComponent"
FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_products_customizableProductOption_updated_at" ON products."customizableProductComponent" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_products_productOption_updated_at"
BEFORE
UPDATE ON products."productOption"
FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_products_productOption_updated_at" ON products."productOption" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_products_product_updated_at
BEFORE
UPDATE ON products.product
FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_products_product_updated_at ON products.product IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_safety_safetyCheck_updated_at"
BEFORE
UPDATE ON safety."safetyCheck"
FOR EACH ROW EXECUTE FUNCTION safety.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_safety_safetyCheck_updated_at" ON safety."safetyCheck" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_apps_updated_at
BEFORE
UPDATE ON settings.app
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_settings_apps_updated_at ON settings.app IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_settings_operationConfig_updated_at"
BEFORE
UPDATE ON settings."operationConfig"
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_settings_operationConfig_updated_at" ON settings."operationConfig" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_role_app_updated_at
BEFORE
UPDATE ON settings.role_app
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_settings_role_app_updated_at ON settings.role_app IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_roles_updated_at
BEFORE
UPDATE ON settings.role
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_settings_roles_updated_at ON settings.role IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_settings_user_role_updated_at
BEFORE
UPDATE ON settings.user_role
FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_settings_user_role_updated_at ON settings.user_role IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_simpleRecipe_simpleRecipe_updated_at"
BEFORE
UPDATE ON "simpleRecipe"."simpleRecipe"
FOR EACH ROW EXECUTE FUNCTION "simpleRecipe".set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_simpleRecipe_simpleRecipe_updated_at" ON "simpleRecipe"."simpleRecipe" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionOccurence_addOn_updated_at"
BEFORE
UPDATE ON subscription."subscriptionOccurence_addOn"
FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_subscription_subscriptionOccurence_addOn_updated_at" ON subscription."subscriptionOccurence_addOn" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionOccurence_product_updated_at"
BEFORE
UPDATE ON subscription."subscriptionOccurence_product"
FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_subscription_subscriptionOccurence_product_updated_at" ON subscription."subscriptionOccurence_product" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionPickupOption_updated_at"
BEFORE
UPDATE ON subscription."subscriptionPickupOption"
FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_subscription_subscriptionPickupOption_updated_at" ON subscription."subscriptionPickupOption" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER "set_subscription_subscriptionTitle_updated_at"
BEFORE
UPDATE ON subscription."subscriptionTitle"
FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at(); COMMENT ON TRIGGER "set_subscription_subscriptionTitle_updated_at" ON subscription."subscriptionTitle" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_website_website_updated_at
BEFORE
UPDATE ON website.website
FOR EACH ROW EXECUTE FUNCTION website.set_current_timestamp_updated_at(); COMMENT ON TRIGGER set_website_website_updated_at ON website.website IS 'trigger to set value of column "updated_at" to current timestamp on row update';
ALTER TABLE ONLY brands.brand ADD CONSTRAINT "brand_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY brands."brand_paymentPartnership" ADD CONSTRAINT "brand_paymentPartnership_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY brands."brand_storeSetting" ADD CONSTRAINT "brand_storeSetting_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY brands."brand_storeSetting" ADD CONSTRAINT "brand_storeSetting_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY brands."brand_storeSetting" ADD CONSTRAINT "brand_storeSetting_storeSettingId_fkey"
FOREIGN KEY ("storeSettingId") REFERENCES brands."storeSetting"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY brands."brand_subscriptionStoreSetting" ADD CONSTRAINT "brand_subscriptionStoreSetting_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY brands."brand_subscriptionStoreSetting" ADD CONSTRAINT "brand_subscriptionStoreSetting_subscriptionStoreSettingId_fk"
FOREIGN KEY ("subscriptionStoreSettingId") REFERENCES brands."subscriptionStoreSetting"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY content.identifier ADD CONSTRAINT "identifier_pageTitle_fkey"
FOREIGN KEY ("pageTitle") REFERENCES content.page(title) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY content."subscriptionDivIds" ADD CONSTRAINT "subscriptionDivIds_fileId_fkey"
FOREIGN KEY ("fileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_customer ADD CONSTRAINT "brandCustomer_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_customer ADD CONSTRAINT "brandCustomer_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY crm.brand_campaign ADD CONSTRAINT "brand_campaign_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_campaign ADD CONSTRAINT "brand_campaign_campaignId_fkey"
FOREIGN KEY ("campaignId") REFERENCES crm.campaign(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_coupon ADD CONSTRAINT "brand_coupon_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_coupon ADD CONSTRAINT "brand_coupon_couponId_fkey"
FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.brand_customer ADD CONSTRAINT "brand_customer_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.campaign ADD CONSTRAINT "campaign_conditionId_fkey"
FOREIGN KEY ("conditionId") REFERENCES rules.conditions(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.campaign ADD CONSTRAINT campaign_type_fkey
FOREIGN KEY (type) REFERENCES crm."campaignType"(value) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.coupon ADD CONSTRAINT "coupon_visibleConditionId_fkey"
FOREIGN KEY ("visibleConditionId") REFERENCES rules.conditions(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_campaignId_fkey"
FOREIGN KEY ("referralCampaignId") REFERENCES crm.campaign(id);
ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."customerReferral" ADD CONSTRAINT "customerReferral_referredByCode_fkey"
FOREIGN KEY ("referredByCode") REFERENCES crm."customerReferral"("referralCode") ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY crm.customer ADD CONSTRAINT "customer_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPointTransaction" ADD CONSTRAINT "loyaltyPointTransaction_customerReferralId_fkey"
FOREIGN KEY ("customerReferralId") REFERENCES crm."customerReferral"(id) ON
DELETE
SET NULL;
ALTER TABLE ONLY crm."loyaltyPointTransaction" ADD CONSTRAINT "loyaltyPointTransaction_loyaltyPointId_fkey"
FOREIGN KEY ("loyaltyPointId") REFERENCES crm."loyaltyPoint"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPointTransaction" ADD CONSTRAINT "loyaltyPointTransaction_orderCartId_fkey"
FOREIGN KEY ("orderCartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY crm."loyaltyPoint" ADD CONSTRAINT "loyaltyPoint_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."loyaltyPoint" ADD CONSTRAINT "loyaltyPoint_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."orderCart_rewards" ADD CONSTRAINT "orderCart_rewards_orderCartId_fkey"
FOREIGN KEY ("orderCartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY crm."orderCart_rewards" ADD CONSTRAINT "orderCart_rewards_rewardId_fkey"
FOREIGN KEY ("rewardId") REFERENCES crm.reward(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_campaignId_fkey"
FOREIGN KEY ("campaignId") REFERENCES crm.campaign(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_couponId_fkey"
FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_loyaltyPointTransactionId_fkey"
FOREIGN KEY ("loyaltyPointTransactionId") REFERENCES crm."loyaltyPointTransaction"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_orderCartId_fkey"
FOREIGN KEY ("orderCartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_orderId_fkey"
FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_rewardId_fkey"
FOREIGN KEY ("rewardId") REFERENCES crm.reward(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardHistory" ADD CONSTRAINT "rewardHistory_walletTransactionId_fkey"
FOREIGN KEY ("walletTransactionId") REFERENCES crm."walletTransaction"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardType_campaignType" ADD CONSTRAINT "rewardType_campaignType_campaignTypeId_fkey"
FOREIGN KEY ("campaignTypeId") REFERENCES crm."campaignType"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."rewardType_campaignType" ADD CONSTRAINT "rewardType_campaignType_rewardTypeId_fkey"
FOREIGN KEY ("rewardTypeId") REFERENCES crm."rewardType"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.reward ADD CONSTRAINT "reward_campaignId_fkey"
FOREIGN KEY ("campaignId") REFERENCES crm.campaign(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.reward ADD CONSTRAINT "reward_conditionId_fkey"
FOREIGN KEY ("conditionId") REFERENCES rules.conditions(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.reward ADD CONSTRAINT "reward_couponId_fkey"
FOREIGN KEY ("couponId") REFERENCES crm.coupon(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm."walletTransaction" ADD CONSTRAINT "walletTransaction_customerReferralId_fkey"
FOREIGN KEY ("customerReferralId") REFERENCES crm."customerReferral"(id);
ALTER TABLE ONLY crm."walletTransaction" ADD CONSTRAINT "walletTransaction_orderCartId_fkey"
FOREIGN KEY ("orderCartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY crm."walletTransaction" ADD CONSTRAINT "walletTransaction_walletId_fkey"
FOREIGN KEY ("walletId") REFERENCES crm.wallet(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.wallet ADD CONSTRAINT "wallet_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY crm.wallet ADD CONSTRAINT "wallet_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".printer ADD CONSTRAINT "printer_computerId_fkey"
FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer("printNodeId") ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "deviceHub".printer ADD CONSTRAINT "printer_printerType_fkey"
FOREIGN KEY ("printerType") REFERENCES "deviceHub"."printerType"(type) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".scale ADD CONSTRAINT "scale_computerId_fkey"
FOREIGN KEY ("computerId") REFERENCES "deviceHub".computer("printNodeId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "deviceHub".scale ADD CONSTRAINT "scale_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY editor."cssFileLinks" ADD CONSTRAINT "cssFileLinks_cssFileId_fkey"
FOREIGN KEY ("cssFileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY editor."cssFileLinks" ADD CONSTRAINT "cssFileLinks_guiFileId_fkey"
FOREIGN KEY ("guiFileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY editor."jsFileLinks" ADD CONSTRAINT "jsFileLinks_guiFileId_fkey"
FOREIGN KEY ("guiFileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY editor."jsFileLinks" ADD CONSTRAINT "jsFileLinks_jsFileId_fkey"
FOREIGN KEY ("jsFileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY fulfilment.brand_recurrence ADD CONSTRAINT "brand_recurrence_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment.brand_recurrence ADD CONSTRAINT "brand_recurrence_recurrenceId_fkey"
FOREIGN KEY ("recurrenceId") REFERENCES fulfilment.recurrence(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment.charge ADD CONSTRAINT "charge_mileRangeId_fkey"
FOREIGN KEY ("mileRangeId") REFERENCES fulfilment."mileRange"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge" ADD CONSTRAINT "deliveryPreferenceByCharge_chargeId_fkey"
FOREIGN KEY ("chargeId") REFERENCES fulfilment.charge(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment."deliveryPreferenceByCharge" ADD CONSTRAINT "deliveryPreferenceByCharge_clauseId_fkey"
FOREIGN KEY ("clauseId") REFERENCES fulfilment."deliveryService"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment."mileRange" ADD CONSTRAINT "mileRange_timeSlotId_fkey"
FOREIGN KEY ("timeSlotId") REFERENCES fulfilment."timeSlot"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY fulfilment.recurrence ADD CONSTRAINT recurrence_type_fkey
FOREIGN KEY (type) REFERENCES fulfilment."fulfillmentType"(value) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY fulfilment."timeSlot" ADD CONSTRAINT "timeSlot_recurrenceId_fkey"
FOREIGN KEY ("recurrenceId") REFERENCES fulfilment.recurrence(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY imports."importHistory" ADD CONSTRAINT "importHistory_importId_fkey"
FOREIGN KEY ("importId") REFERENCES imports.import(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientProcessing" ADD CONSTRAINT "ingredientProcessing_ingredientId_fkey"
FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientProcessing" ADD CONSTRAINT "ingredientProcessing_processingName_fkey"
FOREIGN KEY ("processingName") REFERENCES master."processingName"(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientSacahet_recipeHubSachet" ADD CONSTRAINT "ingredientSacahet_recipeHubSachet_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."ingredientSachet" ADD CONSTRAINT "ingredientSachet_ingredientId_fkey"
FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientSachet" ADD CONSTRAINT "ingredientSachet_ingredientProcessingId_fkey"
FOREIGN KEY ("ingredientProcessingId") REFERENCES ingredient."ingredientProcessing"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY ingredient."ingredientSachet" ADD CONSTRAINT "ingredientSachet_liveMOF_fkey"
FOREIGN KEY ("liveMOF") REFERENCES ingredient."modeOfFulfillment"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."ingredientSachet" ADD CONSTRAINT "ingredientSachet_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_labelTemplateId_fkey"
FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_operationalConfigId_fkey"
FOREIGN KEY ("operationConfigId") REFERENCES settings."operationConfig"(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY ingredient."modeOfFulfillment" ADD CONSTRAINT "modeOfFulfillment_type_fkey"
FOREIGN KEY (type) REFERENCES ingredient."modeOfFulfillmentEnum"(value) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY insights.app_module_insight ADD CONSTRAINT "app_module_insight_insightIdentifier_fkey"
FOREIGN KEY ("insightIdentifier") REFERENCES insights.insights(identifier) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY insights.chart ADD CONSTRAINT "chart_insisghtsTitle_fkey"
FOREIGN KEY ("insightIdentifier") REFERENCES insights.insights(identifier) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY insights.date ADD CONSTRAINT date_day_fkey
FOREIGN KEY (day) REFERENCES insights.day("dayName") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY instructions."instructionStep" ADD CONSTRAINT "instructionStep_instructionSetId_fkey"
FOREIGN KEY ("instructionSetId") REFERENCES instructions."instructionSet"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY instructions."instructionSet" ADD CONSTRAINT "instruction_simpleRecipeId_fkey"
FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_purchaseOrderItemId_fkey"
FOREIGN KEY ("purchaseOrderItemId") REFERENCES inventory."purchaseOrderItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_sachetWorkOrderId_fkey"
FOREIGN KEY ("sachetWorkOrderId") REFERENCES inventory."sachetWorkOrder"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItemHistory" ADD CONSTRAINT "bulkItemHistory_workOrderId_fkey"
FOREIGN KEY ("bulkWorkOrderId") REFERENCES inventory."bulkWorkOrder"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem" ADD CONSTRAINT "bulkItem_processingName_fkey"
FOREIGN KEY ("processingName") REFERENCES master."processingName"(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem" ADD CONSTRAINT "bulkItem_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem_unitConversion" ADD CONSTRAINT "bulkItem_unitConversion_bulkItemId_fkey"
FOREIGN KEY ("entityId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem_unitConversion" ADD CONSTRAINT "bulkItem_unitConversion_unitConversionId_fkey"
FOREIGN KEY ("unitConversionId") REFERENCES master."unitConversion"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkItem" ADD CONSTRAINT "bulkItem_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_inputBulkItemId_fkey"
FOREIGN KEY ("inputBulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_inputQuantityUnit_fkey"
FOREIGN KEY ("inputQuantityUnit") REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_outputBulkItemId_fkey"
FOREIGN KEY ("outputBulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."bulkWorkOrder" ADD CONSTRAINT "bulkWorkOrder_userId_fkey"
FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."packagingHistory" ADD CONSTRAINT "packagingHistory_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."packagingHistory" ADD CONSTRAINT "packagingHistory_purchaseOrderItemId_fkey"
FOREIGN KEY ("purchaseOrderItemId") REFERENCES inventory."purchaseOrderItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_supplier_fkey"
FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."purchaseOrderItem" ADD CONSTRAINT "purchaseOrderItem_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItem" ADD CONSTRAINT "sachetItem2_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItem" ADD CONSTRAINT "sachetItem2_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory" ADD CONSTRAINT "sachetItemHistory_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory" ADD CONSTRAINT "sachetItemHistory_sachetWorkOrderId_fkey"
FOREIGN KEY ("sachetWorkOrderId") REFERENCES inventory."sachetWorkOrder"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetItemHistory" ADD CONSTRAINT "sachetItemHistory_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_inputBulkItemId_fkey"
FOREIGN KEY ("inputBulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_outputSachetItemId_fkey"
FOREIGN KEY ("outputSachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."sachetWorkOrder" ADD CONSTRAINT "sachetWorkOrder_userId_fkey"
FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem" ADD CONSTRAINT "supplierItem_importId_fkey"
FOREIGN KEY ("importId") REFERENCES imports."importHistory"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY inventory."supplierItem" ADD CONSTRAINT "supplierItem_supplierId_fkey"
FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem_unitConversion" ADD CONSTRAINT "supplierItem_unitConversion_entityId_fkey"
FOREIGN KEY ("entityId") REFERENCES inventory."supplierItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem_unitConversion" ADD CONSTRAINT "supplierItem_unitConversion_unitConversionId_fkey"
FOREIGN KEY ("unitConversionId") REFERENCES master."unitConversion"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."supplierItem" ADD CONSTRAINT "supplierItem_unit_fkey"
FOREIGN KEY (unit) REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory.supplier ADD CONSTRAINT "supplier_importId_fkey"
FOREIGN KEY ("importId") REFERENCES imports."importHistory"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY inventory."unitConversionByBulkItem" ADD CONSTRAINT "unitConversionByBulkItem_bulkItemId_fkey"
FOREIGN KEY ("bulkItemId") REFERENCES inventory."bulkItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY inventory."unitConversionByBulkItem" ADD CONSTRAINT "unitConversionByBulkItem_unitConversionId_fkey"
FOREIGN KEY ("unitConversionId") REFERENCES master."unitConversion"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY master."productCategory" ADD CONSTRAINT "productCategory_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY master."unitConversion" ADD CONSTRAINT "unitConversion_inputUnit_fkey"
FOREIGN KEY ("inputUnitName") REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY master."unitConversion" ADD CONSTRAINT "unitConversion_outputUnit_fkey"
FOREIGN KEY ("outputUnitName") REFERENCES master.unit(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY notifications."emailConfig" ADD CONSTRAINT "emailConfig_typeId_fkey"
FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY notifications."displayNotification" ADD CONSTRAINT "notification_typeId_fkey"
FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY notifications."printConfig" ADD CONSTRAINT "printConfig_printerPrintNodeId_fkey"
FOREIGN KEY ("printerPrintNodeId") REFERENCES "deviceHub".printer("printNodeId") ON
DELETE
SET NULL;
ALTER TABLE ONLY notifications."printConfig" ADD CONSTRAINT "printConfig_typeId_fkey"
FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY notifications."smsConfig" ADD CONSTRAINT "smsConfig_typeId_fkey"
FOREIGN KEY ("typeId") REFERENCES notifications.type(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "onDemand".brand_collection ADD CONSTRAINT "brand_collection_collectionId_fkey"
FOREIGN KEY ("collectionId") REFERENCES "onDemand".collection(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand".brand_collection ADD CONSTRAINT "brand_collection_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand".collection ADD CONSTRAINT "collection_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory" ADD CONSTRAINT "collection_productCategory_collectionId_fkey"
FOREIGN KEY ("collectionId") REFERENCES "onDemand".collection(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory" ADD CONSTRAINT "collection_productCategory_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory" ADD CONSTRAINT "collection_productCategory_productCategoryName_fkey"
FOREIGN KEY ("productCategoryName") REFERENCES master."productCategory"(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product" ADD CONSTRAINT "collection_productCategory_product_collection_productCategor"
FOREIGN KEY ("collection_productCategoryId") REFERENCES "onDemand"."collection_productCategory"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product" ADD CONSTRAINT "collection_productCategory_product_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."collection_productCategory_product" ADD CONSTRAINT "collection_productCategory_product_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."modifierCategoryOption" ADD CONSTRAINT "modifierCategoryOption_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY "onDemand"."modifierCategoryOption" ADD CONSTRAINT "modifierCategoryOption_modifierCategoryId_fkey"
FOREIGN KEY ("modifierCategoryId") REFERENCES "onDemand"."modifierCategory"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand"."modifierCategoryOption" ADD CONSTRAINT "modifierCategoryOption_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY "onDemand"."modifierCategoryOption" ADD CONSTRAINT "modifierCategoryOption_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY "onDemand"."modifierCategory" ADD CONSTRAINT "modifierCategory_modifierTemplateId_fkey"
FOREIGN KEY ("modifierTemplateId") REFERENCES "onDemand".modifier(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand".modifier ADD CONSTRAINT "modifier_importHistoryId_fkey"
FOREIGN KEY ("importHistoryId") REFERENCES imports."importHistory"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "onDemand".brand_collection ADD CONSTRAINT "shop_collection_shopId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_cartId_fkey"
FOREIGN KEY ("cartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_comboProductComponentId_fkey"
FOREIGN KEY ("comboProductComponentId") REFERENCES products."comboProductComponent"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_customizableProductComponentId_fkey"
FOREIGN KEY ("customizableProductComponentId") REFERENCES products."customizableProductComponent"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_labelTemplateId_fkey"
FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_parentCartItemId_fkey"
FOREIGN KEY ("parentCartItemId") REFERENCES "order"."cartItem"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_productOptionId_fkey"
FOREIGN KEY ("productOptionId") REFERENCES products."productOption"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_simpleRecipeYieldId_fkey"
FOREIGN KEY ("simpleRecipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."cartItem" ADD CONSTRAINT "cartItem_subscriptionOccurenceProductId_fkey"
FOREIGN KEY ("subscriptionOccurenceProductId") REFERENCES subscription."subscriptionOccurence_product"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order".cart ADD CONSTRAINT "cart_orderId_fkey"
FOREIGN KEY ("orderId") REFERENCES "order"."order"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "order"."order" ADD CONSTRAINT "order_cartId_fkey"
FOREIGN KEY ("cartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "order"."order" ADD CONSTRAINT "order_deliveryPartnershipId_fkey"
FOREIGN KEY ("deliveryPartnershipId") REFERENCES fulfilment."deliveryService"("partnershipId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY "order"."order" ADD CONSTRAINT "order_thirdPartyOrderId_fkey"
FOREIGN KEY ("thirdPartyOrderId") REFERENCES "order"."thirdPartyOrder"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY packaging.packaging ADD CONSTRAINT "packaging_packagingSpecificationsId_fkey"
FOREIGN KEY ("packagingSpecificationsId") REFERENCES packaging."packagingSpecifications"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY packaging.packaging ADD CONSTRAINT "packaging_supplierId_fkey"
FOREIGN KEY ("supplierId") REFERENCES inventory.supplier(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY products."comboProductComponent" ADD CONSTRAINT "comboProductComponent_linkedProductId_fkey"
FOREIGN KEY ("linkedProductId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."comboProductComponent" ADD CONSTRAINT "comboProductComponent_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY products."customizableProductComponent" ADD CONSTRAINT "customizableProductOption_linkedProductId_fkey"
FOREIGN KEY ("linkedProductId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY products."customizableProductComponent" ADD CONSTRAINT "customizableProductOption_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY products."inventoryProductBundleSachet" ADD CONSTRAINT "inventoryProductBundleSachet_inventoryProductBundleId_fkey"
FOREIGN KEY ("inventoryProductBundleId") REFERENCES products."inventoryProductBundle"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY products."productOptionType" ADD CONSTRAINT "productOptionType_orderMode_fkey"
FOREIGN KEY ("orderMode") REFERENCES "order"."orderMode"(title) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_modifierId_fkey"
FOREIGN KEY ("modifierId") REFERENCES "onDemand".modifier(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_operationConfigId_fkey"
FOREIGN KEY ("operationConfigId") REFERENCES settings."operationConfig"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_productId_fkey"
FOREIGN KEY ("productId") REFERENCES products.product(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_sachetItemId_fkey"
FOREIGN KEY ("sachetItemId") REFERENCES inventory."sachetItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_simpleRecipeYieldId_fkey"
FOREIGN KEY ("simpleRecipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY products."productOption" ADD CONSTRAINT "productOption_supplierItemId_fkey"
FOREIGN KEY ("supplierItemId") REFERENCES inventory."supplierItem"(id) ON
UPDATE CASCADE ON
DELETE
SET NULL;
ALTER TABLE ONLY safety."safetyCheckPerUser" ADD CONSTRAINT "safetyCheckByUser_SafetyCheckId_fkey"
FOREIGN KEY ("SafetyCheckId") REFERENCES safety."safetyCheck"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY safety."safetyCheckPerUser" ADD CONSTRAINT "safetyCheckByUser_userId_fkey"
FOREIGN KEY ("userId") REFERENCES settings."user"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."appPermission" ADD CONSTRAINT "appPermission_appId_fkey"
FOREIGN KEY ("appId") REFERENCES settings.app(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.app_module ADD CONSTRAINT "app_module_appTitle_fkey"
FOREIGN KEY ("appTitle") REFERENCES settings.app(title) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."operationConfig" ADD CONSTRAINT "operationConfig_labelTemplateId_fkey"
FOREIGN KEY ("labelTemplateId") REFERENCES "deviceHub"."labelTemplate"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."operationConfig" ADD CONSTRAINT "operationConfig_packagingId_fkey"
FOREIGN KEY ("packagingId") REFERENCES packaging.packaging(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."operationConfig" ADD CONSTRAINT "operationConfig_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."role_appPermission" ADD CONSTRAINT "role_appPermission_appPermissionId_fkey"
FOREIGN KEY ("appPermissionId") REFERENCES settings."appPermission"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings."role_appPermission" ADD CONSTRAINT "role_appPermission_role_appId_fkey"
FOREIGN KEY ("role_appId") REFERENCES settings.role_app(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.role_app ADD CONSTRAINT "role_app_appId_fkey"
FOREIGN KEY ("appId") REFERENCES settings.app(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.role_app ADD CONSTRAINT "role_app_roleId_fkey"
FOREIGN KEY ("roleId") REFERENCES settings.role(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.station ADD CONSTRAINT "station_defaultKotPrinterId_fkey"
FOREIGN KEY ("defaultKotPrinterId") REFERENCES "deviceHub".printer("printNodeId") ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY settings.station ADD CONSTRAINT "station_defaultLabelPrinterId_fkey"
FOREIGN KEY ("defaultLabelPrinterId") REFERENCES "deviceHub".printer("printNodeId") ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY settings.station_kot_printer ADD CONSTRAINT "station_kot_printer_printNodeId_fkey"
FOREIGN KEY ("printNodeId") REFERENCES "deviceHub".printer("printNodeId") ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY settings.station_kot_printer ADD CONSTRAINT "station_kot_printer_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.station_label_printer ADD CONSTRAINT "station_label_printer_printNodeId_fkey"
FOREIGN KEY ("printNodeId") REFERENCES "deviceHub".printer("printNodeId") ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY settings.station_label_printer ADD CONSTRAINT "station_printer_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY settings.station_user ADD CONSTRAINT "station_user_stationId_fkey"
FOREIGN KEY ("stationId") REFERENCES settings.station(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY settings.station_user ADD CONSTRAINT "station_user_userKeycloakId_fkey"
FOREIGN KEY ("userKeycloakId") REFERENCES settings."user"("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.user_role ADD CONSTRAINT "user_role_roleId_fkey"
FOREIGN KEY ("roleId") REFERENCES settings.role(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY settings.user_role ADD CONSTRAINT "user_role_userId_fkey"
FOREIGN KEY ("userId") REFERENCES settings."user"("keycloakId") ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet" ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_ingredientSachetId_fkey"
FOREIGN KEY ("ingredientSachetId") REFERENCES ingredient."ingredientSachet"(id) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet" ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_recipeYieldId_fkey"
FOREIGN KEY ("recipeYieldId") REFERENCES "simpleRecipe"."simpleRecipeYield"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield_ingredientSachet" ADD CONSTRAINT "simpleRecipeYield_ingredientSachet_simpleRecipeIngredientPro"
FOREIGN KEY ("simpleRecipeIngredientProcessingId") REFERENCES "simpleRecipe"."simpleRecipe_ingredient_processing"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipeYield" ADD CONSTRAINT "simpleRecipeYield_simpleRecipeId_fkey"
FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe" ADD CONSTRAINT "simpleRecipe_cuisine_fkey"
FOREIGN KEY (cuisine) REFERENCES master."cuisineName"(name) ON
UPDATE CASCADE ON
DELETE RESTRICT;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe_ingredient_processing" ADD CONSTRAINT "simpleRecipe_ingredient_processing_ingredientId_fkey"
FOREIGN KEY ("ingredientId") REFERENCES ingredient.ingredient(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe_ingredient_processing" ADD CONSTRAINT "simpleRecipe_ingredient_processing_processingId_fkey"
FOREIGN KEY ("processingId") REFERENCES ingredient."ingredientProcessing"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY "simpleRecipe"."simpleRecipe_ingredient_processing" ADD CONSTRAINT "simpleRecipe_ingredient_processing_simpleRecipeId_fkey"
FOREIGN KEY ("simpleRecipeId") REFERENCES "simpleRecipe"."simpleRecipe"(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."brand_subscriptionTitle" ADD CONSTRAINT "brand_subscriptionTitle_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionItemCount" ADD CONSTRAINT "subscriptionItemCount_subscriptionServingId_fkey"
FOREIGN KEY ("subscriptionServingId") REFERENCES subscription."subscriptionServing"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence_addOn" ADD CONSTRAINT "subscriptionOccurence_addOn_productOptionId_fkey"
FOREIGN KEY ("productOptionId") REFERENCES products."productOption"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_brand_customerId_fkey"
FOREIGN KEY ("brand_customerId") REFERENCES crm.brand_customer(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_keycloakId_fkey"
FOREIGN KEY ("keycloakId") REFERENCES crm.customer("keycloakId") ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_orderCartId_fkey"
FOREIGN KEY ("cartId") REFERENCES "order".cart(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_customer" ADD CONSTRAINT "subscriptionOccurence_customer_subscriptionOccurenceId_fkey"
FOREIGN KEY ("subscriptionOccurenceId") REFERENCES subscription."subscriptionOccurence"(id) ON
UPDATE
SET NULL ON
DELETE
SET NULL;
ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_productCategory_fkey"
FOREIGN KEY ("productCategory") REFERENCES master."productCategory"(name) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_productOptionId_fkey"
FOREIGN KEY ("productOptionId") REFERENCES products."productOption"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence_product" ADD CONSTRAINT "subscriptionOccurence_product_subscriptionOccurenceId_fkey"
FOREIGN KEY ("subscriptionOccurenceId") REFERENCES subscription."subscriptionOccurence"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionOccurence" ADD CONSTRAINT "subscriptionOccurence_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionServing" ADD CONSTRAINT "subscriptionServing_defaultSubscriptionItemCountId_fkey"
FOREIGN KEY ("defaultSubscriptionItemCountId") REFERENCES subscription."subscriptionItemCount"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY subscription."subscriptionServing" ADD CONSTRAINT "subscriptionServing_subscriptionTitleId_fkey"
FOREIGN KEY ("subscriptionTitleId") REFERENCES subscription."subscriptionTitle"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription."subscriptionTitle" ADD CONSTRAINT "subscriptionTitle_defaultSubscriptionServingId_fkey"
FOREIGN KEY ("defaultSubscriptionServingId") REFERENCES subscription."subscriptionServing"(id) ON
UPDATE
SET NULL ON
DELETE
SET NULL;
ALTER TABLE ONLY subscription.subscription ADD CONSTRAINT "subscription_subscriptionItemCountId_fkey"
FOREIGN KEY ("subscriptionItemCountId") REFERENCES subscription."subscriptionItemCount"(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY subscription.subscription_zipcode ADD CONSTRAINT "subscription_zipcode_subscriptionId_fkey"
FOREIGN KEY ("subscriptionId") REFERENCES subscription.subscription(id) ON
UPDATE CASCADE ON
DELETE CASCADE;
ALTER TABLE ONLY subscription.subscription_zipcode ADD CONSTRAINT "subscription_zipcode_subscriptionPickupOptionId_fkey"
FOREIGN KEY ("subscriptionPickupOptionId") REFERENCES subscription."subscriptionPickupOption"(id) ON
UPDATE RESTRICT ON
DELETE
SET NULL;
ALTER TABLE ONLY website."websitePageModule" ADD CONSTRAINT "websitePageModule_fileId_fkey"
FOREIGN KEY ("fileId") REFERENCES editor.file(id) ON
UPDATE RESTRICT ON
DELETE CASCADE;
ALTER TABLE ONLY website."websitePageModule" ADD CONSTRAINT "websitePageModule_templateId_fkey"
FOREIGN KEY ("templateId") REFERENCES editor.template(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY website."websitePageModule" ADD CONSTRAINT "websitePageModule_websitePageId_fkey"
FOREIGN KEY ("websitePageId") REFERENCES website."websitePage"(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY website."websitePage" ADD CONSTRAINT "websitePage_websiteId_fkey"
FOREIGN KEY ("websiteId") REFERENCES website.website(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
ALTER TABLE ONLY website.website ADD CONSTRAINT "website_brandId_fkey"
FOREIGN KEY ("brandId") REFERENCES brands.brand(id) ON
UPDATE RESTRICT ON
DELETE RESTRICT;
