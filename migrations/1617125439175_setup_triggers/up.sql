CREATE TRIGGER "customerWLRTrigger"
AFTER
INSERT
    ON crm.brand_customer FOR EACH ROW EXECUTE FUNCTION crm."createCustomerWLR"();

CREATE TRIGGER "loyaltyPointTransaction"
AFTER
INSERT
    ON crm."loyaltyPointTransaction" FOR EACH ROW EXECUTE FUNCTION crm."processLoyaltyPointTransaction"();

CREATE TRIGGER "rewardsTrigger"
AFTER
INSERT
    OR
UPDATE
    OF "referredByCode" ON crm."customerReferral" FOR EACH ROW EXECUTE FUNCTION crm."rewardsTriggerFunction"();

CREATE TRIGGER "set_crm_brandCustomer_updated_at" BEFORE
UPDATE
    ON crm.brand_customer FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_brandCustomer_updated_at" ON crm.brand_customer IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_crm_campaign_updated_at BEFORE
UPDATE
    ON crm.campaign FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_crm_campaign_updated_at ON crm.campaign IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_crm_customer_updated_at BEFORE
UPDATE
    ON crm.customer FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_crm_customer_updated_at ON crm.customer IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_crm_loyaltyPointTransaction_updated_at" BEFORE
UPDATE
    ON crm."loyaltyPointTransaction" FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_loyaltyPointTransaction_updated_at" ON crm."loyaltyPointTransaction" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_crm_loyaltyPoint_updated_at" BEFORE
UPDATE
    ON crm."loyaltyPoint" FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_loyaltyPoint_updated_at" ON crm."loyaltyPoint" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_crm_rewardHistory_updated_at" BEFORE
UPDATE
    ON crm."rewardHistory" FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_rewardHistory_updated_at" ON crm."rewardHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_crm_walletTransaction_updated_at" BEFORE
UPDATE
    ON crm."walletTransaction" FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_crm_walletTransaction_updated_at" ON crm."walletTransaction" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_crm_wallet_updated_at BEFORE
UPDATE
    ON crm.wallet FOR EACH ROW EXECUTE FUNCTION crm.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_crm_wallet_updated_at ON crm.wallet IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "updateBrand_customer"
AFTER
INSERT
    OR
UPDATE
    OF "subscriptionId" ON crm.brand_customer FOR EACH ROW EXECUTE FUNCTION crm."updateBrand_customer"();

CREATE TRIGGER "updateIsSubscriberTimeStamp"
AFTER
INSERT
    OR
UPDATE
    OF "isSubscriber" ON crm.brand_customer FOR EACH ROW EXECUTE FUNCTION crm.updateissubscribertimestamp();

CREATE TRIGGER "walletTransaction"
AFTER
INSERT
    ON crm."walletTransaction" FOR EACH ROW EXECUTE FUNCTION crm."processWalletTransaction"();

CREATE TRIGGER "set_deviceHub_computer_updated_at" BEFORE
UPDATE
    ON "deviceHub".computer FOR EACH ROW EXECUTE FUNCTION "deviceHub".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_deviceHub_computer_updated_at" ON "deviceHub".computer IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_editor_block_updated_at BEFORE
UPDATE
    ON editor.block FOR EACH ROW EXECUTE FUNCTION editor.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_editor_block_updated_at ON editor.block IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_editor_cssFileLinks_updated_at" BEFORE
UPDATE
    ON editor."cssFileLinks" FOR EACH ROW EXECUTE FUNCTION editor.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_editor_cssFileLinks_updated_at" ON editor."cssFileLinks" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_editor_jsFileLinks_updated_at" BEFORE
UPDATE
    ON editor."jsFileLinks" FOR EACH ROW EXECUTE FUNCTION editor.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_editor_jsFileLinks_updated_at" ON editor."jsFileLinks" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_editor_template_updated_at BEFORE
UPDATE
    ON editor.file FOR EACH ROW EXECUTE FUNCTION editor.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_editor_template_updated_at ON editor.file IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_fulfilment_deliveryPreferenceByCharge_updated_at" BEFORE
UPDATE
    ON fulfilment."deliveryPreferenceByCharge" FOR EACH ROW EXECUTE FUNCTION fulfilment.set_current_timestamp_updated_at();

CREATE TRIGGER "set_ingredient_ingredientProcessing_updated_at" BEFORE
UPDATE
    ON ingredient."ingredientProcessing" FOR EACH ROW EXECUTE FUNCTION ingredient.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_ingredient_ingredientProcessing_updated_at" ON ingredient."ingredientProcessing" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_ingredient_ingredientSachet_updatedAt" BEFORE
UPDATE
    ON ingredient."ingredientSachet" FOR EACH ROW EXECUTE FUNCTION ingredient."set_current_timestamp_updatedAt"();

COMMENT ON TRIGGER "set_ingredient_ingredientSachet_updatedAt" ON ingredient."ingredientSachet" IS 'trigger to set value of column "updatedAt" to current timestamp on row update';

CREATE TRIGGER set_ingredient_ingredient_updated_at BEFORE
UPDATE
    ON ingredient.ingredient FOR EACH ROW EXECUTE FUNCTION ingredient.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_ingredient_ingredient_updated_at ON ingredient.ingredient IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_ingredient_modeOfFulfillment_updated_at" BEFORE
UPDATE
    ON ingredient."modeOfFulfillment" FOR EACH ROW EXECUTE FUNCTION ingredient.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_ingredient_modeOfFulfillment_updated_at" ON ingredient."modeOfFulfillment" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "updateModeOfFulfillment"
AFTER
INSERT
    OR
UPDATE
    OF "ingredientSachetId" ON ingredient."modeOfFulfillment" FOR EACH ROW EXECUTE FUNCTION ingredient."updateModeOfFulfillment"();

CREATE TRIGGER set_insights_insights_updated_at BEFORE
UPDATE
    ON insights.insights FOR EACH ROW EXECUTE FUNCTION insights.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_insights_insights_updated_at ON insights.insights IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_inventory_bulkItemHistory_updated_at" BEFORE
UPDATE
    ON inventory."bulkItemHistory" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_bulkItemHistory_updated_at" ON inventory."bulkItemHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_inventory_bulkItem_updatedAt" BEFORE
UPDATE
    ON inventory."bulkItem" FOR EACH ROW EXECUTE FUNCTION inventory."set_current_timestamp_updatedAt"();

COMMENT ON TRIGGER "set_inventory_bulkItem_updatedAt" ON inventory."bulkItem" IS 'trigger to set value of column "updatedAt" to current timestamp on row update';

CREATE TRIGGER "set_inventory_packagingHistory_updated_at" BEFORE
UPDATE
    ON inventory."packagingHistory" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_packagingHistory_updated_at" ON inventory."packagingHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_inventory_purchaseOrderItem_updated_at" BEFORE
UPDATE
    ON inventory."purchaseOrderItem" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_purchaseOrderItem_updated_at" ON inventory."purchaseOrderItem" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_inventory_sachetItemHistory_updated_at" BEFORE
UPDATE
    ON inventory."sachetItemHistory" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_sachetItemHistory_updated_at" ON inventory."sachetItemHistory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_inventory_sachetWorkOrder_updated_at" BEFORE
UPDATE
    ON inventory."sachetWorkOrder" FOR EACH ROW EXECUTE FUNCTION inventory.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_inventory_sachetWorkOrder_updated_at" ON inventory."sachetWorkOrder" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_notifications_notification_updated_at BEFORE
UPDATE
    ON notifications."displayNotification" FOR EACH ROW EXECUTE FUNCTION notifications.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_notifications_notification_updated_at ON notifications."displayNotification" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_notifications_printConfig_updated_at" BEFORE
UPDATE
    ON notifications."printConfig" FOR EACH ROW EXECUTE FUNCTION notifications.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_notifications_printConfig_updated_at" ON notifications."printConfig" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_onDemand_collection_updated_at" BEFORE
UPDATE
    ON "onDemand".collection FOR EACH ROW EXECUTE FUNCTION "onDemand".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_onDemand_collection_updated_at" ON "onDemand".collection IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_onDemand_modifierCategoryOption_updated_at" BEFORE
UPDATE
    ON "onDemand"."modifierCategoryOption" FOR EACH ROW EXECUTE FUNCTION "onDemand".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_onDemand_modifierCategoryOption_updated_at" ON "onDemand"."modifierCategoryOption" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_onDemand_modifierCategory_updated_at" BEFORE
UPDATE
    ON "onDemand"."modifierCategory" FOR EACH ROW EXECUTE FUNCTION "onDemand".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_onDemand_modifierCategory_updated_at" ON "onDemand"."modifierCategory" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_onDemand_modifier_updated_at" BEFORE
UPDATE
    ON "onDemand".modifier FOR EACH ROW EXECUTE FUNCTION "onDemand".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_onDemand_modifier_updated_at" ON "onDemand".modifier IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "deductLoyaltyPointsPostOrder"
AFTER
INSERT
    ON "order"."order" FOR EACH ROW EXECUTE FUNCTION crm."deductLoyaltyPointsPostOrder"();

CREATE TRIGGER "deductWalletAmountPostOrder"
AFTER
INSERT
    ON "order"."order" FOR EACH ROW EXECUTE FUNCTION crm."deductWalletAmountPostOrder"();

CREATE TRIGGER handle_create_sachets
AFTER
INSERT
    ON "order"."cartItem" FOR EACH ROW EXECUTE FUNCTION "order"."createSachets"();

CREATE TRIGGER "onPaymentSuccess"
AFTER
UPDATE
    OF "paymentStatus" ON "order".cart FOR EACH ROW EXECUTE FUNCTION "order"."onPaymentSuccess"();

CREATE TRIGGER on_cart_item_status_change
AFTER
UPDATE
    OF status ON "order"."cartItem" FOR EACH ROW EXECUTE FUNCTION "order".on_cart_item_status_change();

CREATE TRIGGER on_cart_status_change
AFTER
UPDATE
    OF status ON "order".cart FOR EACH ROW EXECUTE FUNCTION "order".on_cart_status_change();

CREATE TRIGGER "postOrderCouponRewards"
AFTER
INSERT
    ON "order"."order" FOR EACH ROW EXECUTE FUNCTION crm."postOrderCouponRewards"();

CREATE TRIGGER "rewardsTrigger"
AFTER
INSERT
    ON "order"."order" FOR EACH ROW EXECUTE FUNCTION crm."rewardsTriggerFunction"();

CREATE TRIGGER "set_order_orderCartItem_updated_at" BEFORE
UPDATE
    ON "order"."cartItem" FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_order_orderCartItem_updated_at" ON "order"."cartItem" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_order_orderCart_updated_at" BEFORE
UPDATE
    ON "order".cart FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_order_orderCart_updated_at" ON "order".cart IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_order_order_updated_at BEFORE
UPDATE
    ON "order"."order" FOR EACH ROW EXECUTE FUNCTION "order".set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_order_order_updated_at ON "order"."order" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "updateStatementDescriptor"
AFTER
INSERT
    OR
UPDATE
    OF "brandId" ON "order".cart FOR EACH ROW EXECUTE FUNCTION "order"."updateStatementDescriptor"();

CREATE TRIGGER "set_products_comboProductComponent_updated_at" BEFORE
UPDATE
    ON products."comboProductComponent" FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_products_comboProductComponent_updated_at" ON products."comboProductComponent" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_products_customizableProductOption_updated_at" BEFORE
UPDATE
    ON products."customizableProductComponent" FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_products_customizableProductOption_updated_at" ON products."customizableProductComponent" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_products_productOption_updated_at" BEFORE
UPDATE
    ON products."productOption" FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_products_productOption_updated_at" ON products."productOption" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_products_product_updated_at BEFORE
UPDATE
    ON products.product FOR EACH ROW EXECUTE FUNCTION products.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_products_product_updated_at ON products.product IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_safety_safetyCheck_updated_at" BEFORE
UPDATE
    ON safety."safetyCheck" FOR EACH ROW EXECUTE FUNCTION safety.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_safety_safetyCheck_updated_at" ON safety."safetyCheck" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "defineOwnerRole"
AFTER
UPDATE
    OF "keycloakId" ON settings."user" FOR EACH ROW EXECUTE FUNCTION settings.define_owner_role();

CREATE TRIGGER set_settings_apps_updated_at BEFORE
UPDATE
    ON settings.app FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_settings_apps_updated_at ON settings.app IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_settings_operationConfig_updated_at" BEFORE
UPDATE
    ON settings."operationConfig" FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_settings_operationConfig_updated_at" ON settings."operationConfig" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_settings_role_app_updated_at BEFORE
UPDATE
    ON settings.role_app FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_settings_role_app_updated_at ON settings.role_app IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_settings_roles_updated_at BEFORE
UPDATE
    ON settings.role FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_settings_roles_updated_at ON settings.role IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_settings_user_role_updated_at BEFORE
UPDATE
    ON settings.user_role FOR EACH ROW EXECUTE FUNCTION settings.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_settings_user_role_updated_at ON settings.user_role IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_simpleRecipe_simpleRecipe_updated_at" BEFORE
UPDATE
    ON "simpleRecipe"."simpleRecipe" FOR EACH ROW EXECUTE FUNCTION "simpleRecipe".set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_simpleRecipe_simpleRecipe_updated_at" ON "simpleRecipe"."simpleRecipe" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "updateSimpleRecipeYield_ingredientSachet"
AFTER
INSERT
    OR
UPDATE
    OF "recipeYieldId" ON "simpleRecipe"."simpleRecipeYield_ingredientSachet" FOR EACH ROW EXECUTE FUNCTION "simpleRecipe"."updateSimpleRecipeYield_ingredientSachet"();

CREATE TRIGGER "set_subscription_subscriptionOccurence_addOn_updated_at" BEFORE
UPDATE
    ON subscription."subscriptionOccurence_addOn" FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_subscription_subscriptionOccurence_addOn_updated_at" ON subscription."subscriptionOccurence_addOn" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_subscription_subscriptionOccurence_product_updated_at" BEFORE
UPDATE
    ON subscription."subscriptionOccurence_product" FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_subscription_subscriptionOccurence_product_updated_at" ON subscription."subscriptionOccurence_product" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_subscription_subscriptionPickupOption_updated_at" BEFORE
UPDATE
    ON subscription."subscriptionPickupOption" FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_subscription_subscriptionPickupOption_updated_at" ON subscription."subscriptionPickupOption" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "set_subscription_subscriptionTitle_updated_at" BEFORE
UPDATE
    ON subscription."subscriptionTitle" FOR EACH ROW EXECUTE FUNCTION subscription.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_subscription_subscriptionTitle_updated_at" ON subscription."subscriptionTitle" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER "updateSubscription"
AFTER
INSERT
    ON subscription.subscription FOR EACH ROW EXECUTE FUNCTION subscription."updateSubscription"();

CREATE TRIGGER "updateSubscriptionItemCount"
AFTER
INSERT
    ON subscription."subscriptionItemCount" FOR EACH ROW EXECUTE FUNCTION subscription."updateSubscriptionItemCount"();

CREATE TRIGGER "updateSubscriptionOccurence"
AFTER
INSERT
    ON subscription."subscriptionOccurence" FOR EACH ROW EXECUTE FUNCTION subscription."updateSubscriptionOccurence"();

CREATE TRIGGER "updateSubscriptionOccurence_customer" BEFORE
INSERT
    ON subscription."subscriptionOccurence_customer" FOR EACH ROW EXECUTE FUNCTION subscription."updateSubscriptionOccurence_customer"();

CREATE TRIGGER "set_website_navigationMenuItem_updated_at" BEFORE
UPDATE
    ON website."navigationMenuItem" FOR EACH ROW EXECUTE FUNCTION website.set_current_timestamp_updated_at();

COMMENT ON TRIGGER "set_website_navigationMenuItem_updated_at" ON website."navigationMenuItem" IS 'trigger to set value of column "updated_at" to current timestamp on row update';

CREATE TRIGGER set_website_website_updated_at BEFORE
UPDATE
    ON website.website FOR EACH ROW EXECUTE FUNCTION website.set_current_timestamp_updated_at();

COMMENT ON TRIGGER set_website_website_updated_at ON website.website IS 'trigger to set value of column "updated_at" to current timestamp on row update';