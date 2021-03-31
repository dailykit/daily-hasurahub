
CREATE TABLE public.response ( success boolean NOT NULL,
                                               message text NOT NULL);


CREATE TABLE crm.campaign ( id integer DEFAULT public.defaultid('crm'::text, 'campaign'::text, 'id'::text) NOT NULL,
                                                                                                           type text NOT NULL,
                                                                                                                     "metaDetails" jsonb,
                                                                                                                     "conditionId" integer, "isRewardMulti" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                  "isActive" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                   priority integer DEFAULT 1 NOT NULL,
                                                                                                                                                                                                                                              created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                          updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                      "isArchived" boolean DEFAULT false NOT NULL);

COMMENT ON TABLE crm.campaign IS 'This table contains all the campaigns across the system.';

COMMENT ON COLUMN crm.campaign.id IS 'Auto generated id for the campaign table row.';

COMMENT ON COLUMN crm.campaign.type IS 'A campaign can be of many types, differentiating how they are implemented. This type here refers to that. The value in this should come from the campaignType table.';

COMMENT ON COLUMN crm.campaign."metaDetails" IS 'This jsonb value contains all the meta details like title, description and picture for this campaign.';

COMMENT ON COLUMN crm.campaign."conditionId" IS 'This represents the rule condition that would be checked for trueness before considering this campaign for implementation for rewards.';

COMMENT ON COLUMN crm.campaign."isRewardMulti" IS 'A campaign could have many rewards. If this is true, that means that all the valid rewards would be applied to the transaction. If false, it would pick the valid reward with highest priority.';

COMMENT ON COLUMN crm.campaign."isActive" IS 'Whether this campaign is active or not.';

COMMENT ON COLUMN crm.campaign."isArchived" IS 'Marks the deletion of campaign if user attempts to delete it.';


CREATE TABLE crm.coupon ( id integer DEFAULT public.defaultid('crm'::text, 'coupon'::text, 'id'::text) NOT NULL,
                                                                                                       "isActive" boolean DEFAULT false NOT NULL,
                                                                                                                                        "metaDetails" jsonb,
                                                                                                                                        code text NOT NULL,
                                                                                                                                                  "isRewardMulti" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                        "visibleConditionId" integer, "isVoucher" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                        "isArchived" boolean DEFAULT false NOT NULL);

COMMENT ON TABLE crm.coupon IS 'This table contains all the coupons across the system.';

COMMENT ON COLUMN crm.coupon.id IS 'Auto generated id for the coupon table row.';

COMMENT ON COLUMN crm.coupon."isActive" IS 'Whether this coupon is active or not.';

COMMENT ON COLUMN crm.coupon."metaDetails" IS 'This jsonb value contains all the meta details like title, description and picture for this coupon.';

COMMENT ON COLUMN crm.coupon."isRewardMulti" IS 'A coupon could have many rewards. If this is true, that means that all the valid rewards would be applied to the transaction. If false, it would pick the valid reward with highest priority.';

COMMENT ON COLUMN crm.coupon."visibleConditionId" IS 'This represents the rule condition that would be checked for trueness before showing the coupon in the store. Please note that this condition doesn''t check if reward is valid or not but strictly just maintains the visibility of the coupon.';

COMMENT ON COLUMN crm.coupon."isArchived" IS 'Marks the deletion of coupon if user attempts to delete it.';


CREATE TABLE crm."customerData" ( id integer NOT NULL,
                                             data jsonb NOT NULL);


CREATE TABLE editor."priorityFuncTable" ( id integer NOT NULL);


CREATE TABLE fulfilment."mileRange" ( id integer DEFAULT public.defaultid('fulfilment'::text, 'mileRange'::text, 'id'::text) NOT NULL,
                                                                                                                             "from" numeric, "to" numeric, "leadTime" integer, "prepTime" integer, "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                   "timeSlotId" integer, zipcodes jsonb);


CREATE TABLE fulfilment."timeSlot" ( id integer DEFAULT public.defaultid('fulfilment'::text, 'timeSlot'::text, 'id'::text) NOT NULL,
                                                                                                                           "recurrenceId" integer, "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                   "from" time without time zone,
                                                                                                                                                                                                            "to" time without time zone,
                                                                                                                                                                                                                                   "pickUpLeadTime" integer DEFAULT 120,
                                                                                                                                                                                                                                                                    "pickUpPrepTime" integer DEFAULT 30);


CREATE TABLE ingredient."ingredientSachet" ( id integer DEFAULT public.defaultid('ingredient'::text, 'ingredientSachet'::text, 'id'::text) NOT NULL,
                                                                                                                                           quantity numeric NOT NULL,
                                                                                                                                                            "ingredientProcessingId" integer NOT NULL,
                                                                                                                                                                                             "ingredientId" integer NOT NULL,
                                                                                                                                                                                                                    "createdAt" timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                 "updatedAt" timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                              tracking boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                            unit text NOT NULL,
                                                                                                                                                                                                                                                                                                                                                      visibility boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                      "liveMOF" integer, "isArchived" boolean DEFAULT false NOT NULL);


CREATE TABLE ingredient."modeOfFulfillment" ( id integer DEFAULT public.defaultid('ingredient'::text, 'modeOfFulfillment'::text, 'id'::text) NOT NULL,
                                                                                                                                             type text NOT NULL,
                                                                                                                                                       "stationId" integer, "labelTemplateId" integer, "bulkItemId" integer, "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                 "position" numeric, "ingredientSachetId" integer NOT NULL,
                                                                                                                                                                                                                                                                                                                  "packagingId" integer, "isLive" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                        accuracy integer, "sachetItemId" integer, "operationConfigId" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       priority integer DEFAULT 1 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  "ingredientId" integer, "ingredientProcessingId" integer);


CREATE TABLE ingredient.ingredient ( id integer DEFAULT public.defaultid('ingredient'::text, 'ingredient'::text, 'id'::text) NOT NULL,
                                                                                                                             name text NOT NULL,
                                                                                                                                       image text, "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                       category text, "createdAt" date DEFAULT now(),
                                                                                                                                                                                                                               updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                           "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                              assets jsonb);


CREATE TABLE "simpleRecipe"."simpleRecipe" ( id integer DEFAULT public.defaultid('simpleRecipe'::text, 'simpleRecipe'::text, 'id'::text) NOT NULL,
                                                                                                                                         author text, name jsonb NOT NULL,
                                                                                                                                                                 "cookingTime" text, utensils jsonb,
                                                                                                                                                                                     description text, cuisine text, image text, show boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                           assets jsonb,
                                                                                                                                                                                                                                                           type text, "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                          created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                      updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                  "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                     "notIncluded" jsonb,
                                                                                                                                                                                                                                                                                                                                                                                                                                     "showIngredients" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                            "showIngredientsQuantity" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "showProcedures" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 "isSubRecipe" boolean);


CREATE TABLE inventory."supplierItem" ( id integer DEFAULT public.defaultid('inventory'::text, 'supplierItem'::text, 'id'::text) NOT NULL,
                                                                                                                                 name text, "unitSize" integer, prices jsonb,
                                                                                                                                                                "supplierId" integer, unit text, "leadTime" jsonb,
                                                                                                                                                                                                 certificates jsonb,
                                                                                                                                                                                                 "bulkItemAsShippedId" integer, sku text, "importId" integer, "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                 "unitConversionId" integer, "sachetItemAsShippedId" integer);


CREATE TABLE "onDemand".menu ( id integer DEFAULT public.defaultid('onDemand'::text, 'menu'::text, 'id'::text) NOT NULL,
                                                                                                               data jsonb);


CREATE TABLE "onDemand"."collection_productCategory_product" ( "collection_productCategoryId" integer NOT NULL,
                                                                                                      id integer DEFAULT public.defaultid('onDemand'::text, 'collection_productCategory_product'::text, 'id'::text) NOT NULL,
                                                                                                                                                                                                                    "position" numeric, "importHistoryId" integer, "productId" integer NOT NULL);


CREATE TABLE "onDemand"."storeData" ( id integer DEFAULT public.defaultid('onDemand'::text, 'storeData'::text, 'id'::text) NOT NULL,
                                                                                                                           "brandId" integer, settings jsonb);


CREATE TABLE "onDemand"."modifierCategoryOption" ( id integer DEFAULT public.defaultid('onDemand'::text, 'modifierCategoryOption'::text, 'id'::text) NOT NULL,
                                                                                                                                                     name text NOT NULL,
                                                                                                                                                               "originalName" text NOT NULL,
                                                                                                                                                                                   price numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                           discount numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                      quantity integer DEFAULT 1 NOT NULL,
                                                                                                                                                                                                                                                                 image text, "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                             "isVisible" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                              "operationConfigId" integer, "modifierCategoryId" integer NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                        "sachetItemId" integer, "ingredientSachetId" integer, "simpleRecipeYieldId" integer, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE "order".cart ( id integer DEFAULT public.defaultid('order'::text, 'cart'::text, 'id'::text) NOT NULL,
                                                                                                         "paidPrice" numeric DEFAULT 0 NOT NULL,
                                                                                                                                       "customerId" integer, "paymentStatus" text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                                                          status text DEFAULT 'CART_PENDING'::text NOT NULL,
                                                                                                                                                                                                                                                   "paymentMethodId" text, "transactionId" text, "stripeCustomerId" text, "fulfillmentInfo" jsonb,
                                                                                                                                                                                                                                                                                                                          tip numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                address jsonb,
                                                                                                                                                                                                                                                                                                                                                "customerInfo" jsonb,
                                                                                                                                                                                                                                                                                                                                                source text DEFAULT 'a-la-carte'::text NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                       "subscriptionOccurenceId" integer, "walletAmountUsed" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                               "isTest" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              "brandId" integer DEFAULT 1 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          "couponDiscount" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             "loyaltyPointsUsed" integer DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   "paymentId" uuid,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   "paymentUpdatedAt" timestamp with time zone,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          "paymentRequestInfo" jsonb,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              "customerKeycloakId" text, "orderId" integer, amount numeric DEFAULT 0,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   "transactionRemark" jsonb,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   "stripeInvoiceId" text, "stripeInvoiceDetails" jsonb,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "statementDescriptor" text, "paymentRetryAttempt" integer DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               "invoiceSendAttempt" integer DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      "transactionRemarkHistory" jsonb DEFAULT '[]'::jsonb,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               "stripeInvoiceHistory" jsonb DEFAULT '[]'::jsonb);


CREATE TABLE "order"."order" ( id oid DEFAULT public.defaultid('order'::text, 'order'::text, 'id'::text) NOT NULL,
                                                                                                         "deliveryInfo" jsonb,
                                                                                                         created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                           tax double precision, discount numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                            "itemTotal" numeric, "deliveryPrice" numeric, currency text DEFAULT 'usd'::text,
                                                                                                                                                                                                                                                                                updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                            tip numeric, "amountPaid" numeric, "fulfillmentType" text, "deliveryPartnershipId" integer, "cartId" integer, "isRejected" boolean, "isAccepted" boolean, "thirdPartyOrderId" integer, "readyByTimestamp" timestamp without time zone,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             "fulfillmentTimestamp" timestamp without time zone,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "keycloakId" text, "brandId" integer);


CREATE TABLE products."comboProductComponent" ( id integer DEFAULT public.defaultid('products'::text, 'comboProductComponent'::text, 'id'::text) NOT NULL,
                                                                                                                                                 label text NOT NULL,
                                                                                                                                                            created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                        updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                    "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                       options jsonb DEFAULT '[]'::jsonb NOT NULL,
                                                                                                                                                                                                                                                                                                                         "position" numeric, "productId" integer, "linkedProductId" integer);


CREATE TABLE products."customizableProductComponent" ( id integer DEFAULT public.defaultid('products'::text, 'customizableProductComponent'::text, 'id'::text) NOT NULL,
                                                                                                                                                               created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                           updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                       "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                          options jsonb DEFAULT '[]'::jsonb NOT NULL,
                                                                                                                                                                                                                                                                                                                            "position" numeric, "productId" integer, "linkedProductId" integer);


CREATE TABLE products.product (id integer DEFAULT public.defaultid('products'::text, 'product'::text, 'id'::text) NOT NULL,
                                                                                                                  name text, "additionalText" text, description text, assets jsonb DEFAULT jsonb_build_object('images', '[]'::jsonb, 'videos', '[]'::jsonb) NOT NULL,
                                                                                                                                                                                                                                                            "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                "isPopupAllowed" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                      "defaultProductOptionId" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                    updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                tags jsonb,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   type text DEFAULT 'simple'::text NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    price numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            discount numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       "importHistoryId" integer);


CREATE TABLE products."productOption" (id integer DEFAULT public.defaultid('products'::text, 'productOption'::text, 'id'::text) NOT NULL,
                                                                                                                                "productId" integer NOT NULL,
                                                                                                                                                    label text DEFAULT 'Basic'::text NOT NULL,
                                                                                                                                                                                     "modifierId" integer, "operationConfigId" integer, "simpleRecipeYieldId" integer, "supplierItemId" integer, "sachetItemId" integer, "position" numeric, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                         updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                                     price numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                             discount numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        quantity integer DEFAULT 1 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   type text, "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 "inventoryProductBundleId" integer);


CREATE TABLE rules.facts (id integer DEFAULT public.defaultid('rules'::text, 'facts'::text, 'id'::text) NOT NULL,
                                                                                                        query text);


CREATE TABLE rules.conditions (id integer DEFAULT public.defaultid('rules'::text, 'conditions'::text, 'id'::text) NOT NULL,
                                                                                                                  condition jsonb NOT NULL,
                                                                                                                                  app text);


CREATE TABLE settings."operationConfig" (id integer DEFAULT public.defaultid('settings'::text, 'operationConfig'::text, 'id'::text) NOT NULL,
                                                                                                                                    "stationId" integer, "labelTemplateId" integer, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                      updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                        "packagingId" integer);


CREATE TABLE "simpleRecipe"."simpleRecipeYield" (id integer DEFAULT public.defaultid('simpleRecipe'::text, 'simpleRecipeYield'::text, 'id'::text) NOT NULL,
                                                                                                                                                  "simpleRecipeId" integer NOT NULL,
                                                                                                                                                                           yield jsonb NOT NULL,
                                                                                                                                                                                       "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                          quantity numeric, unit text, serving numeric);


CREATE TABLE subscription."subscriptionOccurence_addOn" (id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionOccurence_addOn'::text, 'id'::text) NOT NULL,
                                                                                                                                                                    "subscriptionOccurenceId" integer, "unitPrice" numeric NOT NULL,
                                                                                                                                                                                                                           "productCategory" text, "isAvailable" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                      "isVisible" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                       "isSingleSelect" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                              "subscriptionId" integer, "productOptionId" integer NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                  created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                    updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE subscription."subscriptionOccurence" (id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionOccurence'::text, 'id'::text) NOT NULL,
                                                                                                                                                        "fulfillmentDate" date NOT NULL,
                                                                                                                                                                               "cutoffTimeStamp" timestamp without time zone NOT NULL,
                                                                                                                                                                                                                             "subscriptionId" integer NOT NULL,
                                                                                                                                                                                                                                                      "startTimeStamp" timestamp without time zone,
                                                                                                                                                                                                                                                                                              assets jsonb,
                                                                                                                                                                                                                                                                                              "subscriptionAutoSelectOption" text, "subscriptionItemCountId" integer, "subscriptionServingId" integer, "subscriptionTitleId" integer);


CREATE TABLE subscription."subscriptionOccurence_product" ("subscriptionOccurenceId" integer, "addOnPrice" numeric DEFAULT 0,
                                                                                                                           "addOnLabel" text, "productCategory" text, "isAvailable" boolean DEFAULT true,
                                                                                                                                                                                                    "isVisible" boolean DEFAULT true,
                                                                                                                                                                                                                                "isSingleSelect" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                      "subscriptionId" integer, id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionOccurence_product'::text, 'id'::text) NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                             created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                         updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     "isAutoSelectable" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             "productOptionId" integer NOT NULL);


CREATE TABLE subscription."subscriptionOccurence_customer" ("subscriptionOccurenceId" integer NOT NULL,
                                                                                              "keycloakId" text NOT NULL,
                                                                                                                "cartId" integer, "isSkipped" boolean DEFAULT false NOT NULL,
                                                                                                                                                                    "isAuto" boolean, "brand_customerId" integer NOT NULL,
                                                                                                                                                                                                                 "subscriptionId" integer);


CREATE TABLE subscription."subscriptionItemCount" (id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionItemCount'::text, 'id'::text) NOT NULL,
                                                                                                                                                        "subscriptionServingId" integer NOT NULL,
                                                                                                                                                                                        count integer NOT NULL,
                                                                                                                                                                                                      "metaDetails" jsonb,
                                                                                                                                                                                                      price numeric, "isActive" boolean DEFAULT false,
                                                                                                                                                                                                                                                tax numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                      "isTaxIncluded" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                            "subscriptionTitleId" integer, "targetedProductSelectionRatio" integer DEFAULT 3);


CREATE TABLE subscription."subscriptionServing" (id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionServing'::text, 'id'::text) NOT NULL,
                                                                                                                                                    "subscriptionTitleId" integer NOT NULL,
                                                                                                                                                                                  "servingSize" integer NOT NULL,
                                                                                                                                                                                                        "metaDetails" jsonb,
                                                                                                                                                                                                        "defaultSubscriptionItemCountId" integer, "isActive" boolean DEFAULT false NOT NULL);


CREATE TABLE subscription."subscriptionTitle" (id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionTitle'::text, 'id'::text) NOT NULL,
                                                                                                                                                title text NOT NULL,
                                                                                                                                                           "metaDetails" jsonb,
                                                                                                                                                           "defaultSubscriptionServingId" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                               updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                           "isActive" boolean DEFAULT false NOT NULL);


CREATE TABLE brands.brand (id integer DEFAULT public.defaultid('brands'::text, 'brand'::text, 'id'::text) NOT NULL,
                                                                                                          domain text, "isDefault" boolean DEFAULT false NOT NULL,
                                                                                                                                                         title text, "isPublished" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                        "onDemandRequested" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                  "subscriptionRequested" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                   "parseurMailBoxId" integer, "importHistoryId" integer);

COMMENT ON TABLE brands.brand IS 'This table contains all the brands available in this instance.';

COMMENT ON COLUMN brands.brand.id IS 'Unique id of brand';

COMMENT ON COLUMN brands.brand.domain IS 'Domain at which this particular brand would be operating at.';

COMMENT ON COLUMN brands.brand."isDefault" IS 'This brand would be chosen incase any url is entered that does not correspond to any other brand';

COMMENT ON COLUMN brands.brand.title IS 'This is the title of the brand for internal purpose.';

COMMENT ON COLUMN brands.brand."isPublished" IS 'Whether the brand is published or not';

COMMENT ON COLUMN brands.brand."onDemandRequested" IS 'If this brand would be operating an ondemand store. If false, then opening /store link would redirect.';

COMMENT ON COLUMN brands.brand."subscriptionRequested" IS 'If this brand would be operating an subscription store. If false, then opening /subscription link would redirect.';

COMMENT ON COLUMN brands.brand."isArchived" IS 'if True, means that this brand is no longer active and user attempted to delete it.';

COMMENT ON COLUMN brands.brand."parseurMailBoxId" IS 'This is for parseur mailbox functionality.';


CREATE TABLE brands."brand_paymentPartnership" ("brandId" integer NOT NULL,
                                                                  "paymentPartnershipId" integer NOT NULL,
                                                                                                 "isActive" boolean DEFAULT true NOT NULL);

COMMENT ON TABLE brands."brand_paymentPartnership" IS 'This is a many to many table for maintaining the different payment options available for each brand.';

COMMENT ON COLUMN brands."brand_paymentPartnership"."brandId" IS 'Id of the brand from the brand table.';

COMMENT ON COLUMN brands."brand_paymentPartnership"."paymentPartnershipId" IS 'id of the paymentPartnership from the dailycloak database table of paymentPartnership. This id represents which payment company and what are payment conditions to be used.';

COMMENT ON COLUMN brands."brand_paymentPartnership"."isActive" IS 'Whether this payment partnership is active or not.';


CREATE TABLE brands."brand_storeSetting" ("brandId" integer NOT NULL,
                                                            "storeSettingId" integer NOT NULL,
                                                                                     value jsonb NOT NULL,
                                                                                                 "importHistoryId" integer);

COMMENT ON TABLE brands."brand_storeSetting" IS 'This is a many to many table maintaining Ondemand Store setting for available brands.';

COMMENT ON COLUMN brands."brand_storeSetting"."brandId" IS 'This is the brand id from brand table.';

COMMENT ON COLUMN brands."brand_storeSetting"."storeSettingId" IS 'This is the id from the list of settings available for ondemand.';

COMMENT ON COLUMN brands."brand_storeSetting".value IS 'This is the value of the particular setting for the particular brand.';


CREATE TABLE brands."brand_subscriptionStoreSetting" ("brandId" integer NOT NULL,
                                                                        "subscriptionStoreSettingId" integer NOT NULL,
                                                                                                             value jsonb);

COMMENT ON TABLE brands."brand_subscriptionStoreSetting" IS 'This table maintains list of settings for subscription store for brands.';

COMMENT ON COLUMN brands."brand_subscriptionStoreSetting"."brandId" IS 'This is the brand id from the brand table.';

COMMENT ON COLUMN brands."brand_subscriptionStoreSetting"."subscriptionStoreSettingId" IS 'This is the id from the list of settings available for subscription store.';

COMMENT ON COLUMN brands."brand_subscriptionStoreSetting".value IS 'This is the value of the particular setting for the particular brand.';


CREATE TABLE brands."storeSetting" (id integer DEFAULT public.defaultid('brands'::text, 'storeSetting'::text, 'id'::text) NOT NULL,
                                                                                                                          identifier text NOT NULL,
                                                                                                                                          value jsonb,
                                                                                                                                          type text);

COMMENT ON TABLE brands."storeSetting" IS 'This lists all the available settings for ondemand store.';

COMMENT ON COLUMN brands."storeSetting".id IS 'This is autogenerated id of the setting representation available for ondemand.';

COMMENT ON COLUMN brands."storeSetting".identifier IS 'This is a unique identifier of the individual setting type.';

COMMENT ON COLUMN brands."storeSetting".value IS 'This is a jsonb data type storing default value for the setting. If no brand specific setting is available, then this setting value would be used.';

COMMENT ON COLUMN brands."storeSetting".type IS 'Type of setting to segment or categorize according to different use-cases.';


CREATE TABLE brands."subscriptionStoreSetting" (id integer DEFAULT public.defaultid('brands'::text, 'storeSetting'::text, 'id'::text) NOT NULL,
                                                                                                                                      identifier text NOT NULL,
                                                                                                                                                      value jsonb,
                                                                                                                                                      type text);

COMMENT ON TABLE brands."subscriptionStoreSetting" IS 'This lists all the available settings for ondemand store.';

COMMENT ON COLUMN brands."subscriptionStoreSetting".id IS 'This is autogenerated id of the setting representation available for subscripton.';

COMMENT ON COLUMN brands."subscriptionStoreSetting".identifier IS 'This is a unique identifier of the individual setting type.';

COMMENT ON COLUMN brands."subscriptionStoreSetting".value IS 'This is a jsonb data type storing default value for the setting. If no brand specific setting is available, then this setting value would be used.';

COMMENT ON COLUMN brands."subscriptionStoreSetting".type IS 'Type of setting to segment or categorize according to different use-cases.';


CREATE TABLE content.identifier (title text NOT NULL,
                                            "pageTitle" text NOT NULL);


CREATE TABLE content.page (title text NOT NULL,
                                      description text);


CREATE TABLE content."subscriptionDivIds" (id text NOT NULL,
                                                   "fileId" integer);


CREATE TABLE content.template (id uuid NOT NULL);


CREATE TABLE crm.brand_campaign ("brandId" integer NOT NULL,
                                                   "campaignId" integer NOT NULL,
                                                                        "isActive" boolean DEFAULT true);

COMMENT ON TABLE crm.brand_campaign IS 'This is a many to many table maintaining relationship between brand and campaigns.';

COMMENT ON COLUMN crm.brand_campaign."brandId" IS 'This is the brandId from the brand table.';

COMMENT ON COLUMN crm.brand_campaign."campaignId" IS 'This is campaign id from campaign table.';

COMMENT ON COLUMN crm.brand_campaign."isActive" IS 'Whether this particular campaign is active or not for this brand.';


CREATE TABLE crm.brand_coupon ("brandId" integer NOT NULL,
                                                 "couponId" integer NOT NULL,
                                                                    "isActive" boolean DEFAULT true NOT NULL);

COMMENT ON TABLE crm.brand_coupon IS 'This is a many to many table maintaining relationship between brand and coupons.';

COMMENT ON COLUMN crm.brand_coupon."brandId" IS 'This is the brandId from the brand table.';

COMMENT ON COLUMN crm.brand_coupon."couponId" IS 'This is coupon id from coupon table.';

COMMENT ON COLUMN crm.brand_coupon."isActive" IS 'Whether this particular coupon is active or not for this brand.';


CREATE TABLE crm.brand_customer (id integer DEFAULT public.defaultid('crm'::text, 'brand_customer'::text, 'id'::text) NOT NULL,
                                                                                                                      "keycloakId" text NOT NULL,
                                                                                                                                        "brandId" integer NOT NULL,
                                                                                                                                                          created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                      updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                  "isSubscriber" boolean DEFAULT false,
                                                                                                                                                                                                                                                                                 "subscriptionId" integer, "subscriptionAddressId" text, "subscriptionPaymentMethodId" text, "isAutoSelectOptOut" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                        "isSubscriberTimeStamp" timestamp without time zone,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                       "subscriptionServingId" integer, "subscriptionItemCountId" integer, "subscriptionTitleId" integer);

COMMENT ON TABLE crm.brand_customer IS 'This table maintains a list of all the customers who have signed into this particular brand atleast once.';

COMMENT ON COLUMN crm.brand_customer.id IS 'Auto-generated id.';

COMMENT ON COLUMN crm.brand_customer."keycloakId" IS 'This is the unique id of customer given by keycloak.';

COMMENT ON COLUMN crm.brand_customer."brandId" IS 'This is the brandId from brand table.';

COMMENT ON COLUMN crm.brand_customer."isSubscriber" IS 'If this customer has subscribed to any plan on subscription store for this particular brand.';

COMMENT ON COLUMN crm.brand_customer."subscriptionId" IS 'This is the id of the subscription plan chosen by this customer.';

COMMENT ON COLUMN crm.brand_customer."subscriptionAddressId" IS 'This is the id of address from Dailykey database at which this plan would be delivering the weekly box to.';

COMMENT ON COLUMN crm.brand_customer."subscriptionPaymentMethodId" IS 'This is the id of payment method from Dailykey database defining which particular payment method would be used for auto deduction of weekly amount.';


CREATE TABLE crm."campaignType" (id integer DEFAULT public.defaultid('crm'::text, 'campaignType'::text, 'id'::text) NOT NULL,
                                                                                                                    value text NOT NULL);


CREATE TABLE crm.customer (id integer DEFAULT public.defaultid('crm'::text, 'customer'::text, 'id'::text) NOT NULL,
                                                                                                          source text, email text NOT NULL,
                                                                                                                                  "keycloakId" text NOT NULL,
                                                                                                                                                    "clientId" text, "isSubscriber" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                          "subscriptionId" integer, "subscriptionAddressId" uuid,
                                                                                                                                                                                                                                    "subscriptionPaymentMethodId" text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                    updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                "isTest" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                              "sourceBrandId" integer DEFAULT 1 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                "isArchived" boolean DEFAULT false NOT NULL);

COMMENT ON TABLE crm.customer IS 'This lists records of all the unique customers across all the brands.';

COMMENT ON COLUMN crm.customer.id IS 'Auto-generated id of the customer';

COMMENT ON COLUMN crm.customer.source IS 'From which source this customer was first created. If subscription or ondemand.';

COMMENT ON COLUMN crm.customer.email IS 'Unique email of the customer.';

COMMENT ON COLUMN crm.customer."keycloakId" IS 'This is the unique id of customer given by keycloak.';

COMMENT ON COLUMN crm.customer."isSubscriber" IS 'If this customer has subscribed to any plan on subscription store for any of the brand.';

COMMENT ON COLUMN crm.customer."isTest" IS 'If true, all the carts for this customer would bypass the payment.';

COMMENT ON COLUMN crm.customer."sourceBrandId" IS 'From which brand was this customer first signed up in the system.';

COMMENT ON COLUMN crm.customer."isArchived" IS 'Marks the deletion of customer if user attempts to delete it';


CREATE TABLE crm."customerReferral" (id integer DEFAULT public.defaultid('crm'::text, 'customerReferral'::text, 'id'::text) NOT NULL,
                                                                                                                            "keycloakId" text NOT NULL,
                                                                                                                                              "referralCode" text DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                                                                                                                                   "referredByCode" text, "referralStatus" text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                                                                                                                        "referralCampaignId" integer, "signupCampaignId" integer, "signupStatus" text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                              "brandId" integer DEFAULT 1 NOT NULL);

COMMENT ON TABLE crm."customerReferral" IS 'This table maintains a record of all the customer and brand''s referral codes.';

COMMENT ON COLUMN crm."customerReferral".id IS 'Auto-generated id for the row.';

COMMENT ON COLUMN crm."customerReferral"."keycloakId" IS 'This is the unique id of customer given by keycloak.';

COMMENT ON COLUMN crm."customerReferral"."referralCode" IS 'This is auto generated UUID code created for each customer to share with others for referral.';

COMMENT ON COLUMN crm."customerReferral"."referredByCode" IS 'This is the referral code that was used by the customer for signing up';

COMMENT ON COLUMN crm."customerReferral"."referralStatus" IS 'This denotes the status if the customer who referred was awarded something according to the referral campaign id.';

COMMENT ON COLUMN crm."customerReferral"."referralCampaignId" IS 'The id of the campaign to be used to award the referrer.';

COMMENT ON COLUMN crm."customerReferral"."signupCampaignId" IS 'The id of the campaign to be used to reward this customer who signed up.';

COMMENT ON COLUMN crm."customerReferral"."signupStatus" IS 'This denotes the status if the signed up customer was awarded something according to the  signup campaign id.';

COMMENT ON COLUMN crm."customerReferral"."brandId" IS 'This is the brandId from the brand table.';


CREATE TABLE crm."loyaltyPoint" (id integer DEFAULT public.defaultid('crm'::text, 'loyaltyPoint'::text, 'id'::text) NOT NULL,
                                                                                                                    "keycloakId" text NOT NULL,
                                                                                                                                      points integer DEFAULT 0 NOT NULL,
                                                                                                                                                               "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                               created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                 updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                   "brandId" integer DEFAULT 1 NOT NULL);

COMMENT ON TABLE crm."loyaltyPoint" IS 'This table maintains record of all the loyalty point references of all customers across all brands.';

COMMENT ON COLUMN crm."loyaltyPoint"."keycloakId" IS 'Customer keycloak Id referencing the customer for this row.';

COMMENT ON COLUMN crm."loyaltyPoint".points IS 'Available loyalty points for this customer across the referenced brand in the row.';

COMMENT ON COLUMN crm."loyaltyPoint"."isActive" IS 'If loyalty points for this customer is active.';

COMMENT ON COLUMN crm."loyaltyPoint"."brandId" IS 'Id of the brand for which this loyalty point is created and maintained.';


CREATE TABLE crm."loyaltyPointTransaction" (id integer DEFAULT public.defaultid('crm'::text, 'loyaltyPointTransaction'::text, 'id'::text) NOT NULL,
                                                                                                                                          "loyaltyPointId" integer NOT NULL,
                                                                                                                                                                   points integer NOT NULL,
                                                                                                                                                                                  "orderCartId" integer, type text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                            "amountRedeemed" numeric, "customerReferralId" integer);

COMMENT ON TABLE crm."loyaltyPointTransaction" IS 'This table lists all the loyalty point transactions taking place.';


CREATE TABLE crm."orderCart_rewards" (id integer DEFAULT public.defaultid('crm'::text, 'orderCart_rewards'::text, 'id'::text) NOT NULL,
                                                                                                                              "orderCartId" integer NOT NULL,
                                                                                                                                                    "rewardId" integer NOT NULL);


CREATE TABLE crm.reward (id integer DEFAULT public.defaultid('crm'::text, 'reward'::text, 'id'::text) NOT NULL,
                                                                                                      type text NOT NULL,
                                                                                                                "couponId" integer, "conditionId" integer, priority integer DEFAULT 1,
                                                                                                                                                                                    "campaignId" integer, "rewardValue" jsonb);


CREATE TABLE crm."rewardHistory" (id integer DEFAULT public.defaultid('crm'::text, 'rewardHistory'::text, 'id'::text) NOT NULL,
                                                                                                                      "rewardId" integer NOT NULL,
                                                                                                                                         created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                           updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                             "couponId" integer, "campaignId" integer, "keycloakId" text NOT NULL,
                                                                                                                                                                                                                                                                                                         "orderCartId" integer, "orderId" integer, discount numeric, "loyaltyPointTransactionId" integer, "loyaltyPoints" integer, "walletAmount" numeric, "walletTransactionId" integer, "brandId" integer DEFAULT 1 NOT NULL);


CREATE TABLE crm."rewardType" (id integer DEFAULT public.defaultid('crm'::text, 'rewardType'::text, 'id'::text) NOT NULL,
                                                                                                                value text NOT NULL,
                                                                                                                           "useForCoupon" boolean NOT NULL,
                               handler text NOT NULL);


CREATE TABLE crm."rewardType_campaignType" ("rewardTypeId" integer NOT NULL,
                                                                   "campaignTypeId" integer NOT NULL);


CREATE TABLE crm.wallet (id integer DEFAULT public.defaultid('crm'::text, 'wallet'::text, 'id'::text) NOT NULL,
                                                                                                      "keycloakId" text, amount numeric DEFAULT 0 NOT NULL,
                                                                                                                                                  "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                  created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                              updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                          "brandId" integer DEFAULT 1 NOT NULL);


CREATE TABLE crm."walletTransaction" (id integer DEFAULT public.defaultid('crm'::text, 'walletTransaction'::text, 'id'::text) NOT NULL,
                                                                                                                              "walletId" integer NOT NULL,
                                                                                                                                                 amount numeric NOT NULL,
                                                                                                                                                                type text, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                             updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                               "orderCartId" integer, "customerReferralId" integer);


CREATE TABLE "deviceHub".computer ("printNodeId" integer NOT NULL,
                                                         name text, inet text, inet6 text, hostname text, jre text, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                      updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                        state text, version text);


CREATE TABLE "deviceHub".config (id integer DEFAULT public.defaultid('deviceHub'::text, 'config'::text, 'id'::text) NOT NULL,
                                                                                                                    name text NOT NULL,
                                                                                                                              value jsonb NOT NULL);


CREATE TABLE "deviceHub"."labelTemplate" (id integer DEFAULT public.defaultid('deviceHub'::text, 'labelTemplate'::text, 'id'::text) NOT NULL,
                                                                                                                                    name text NOT NULL);


CREATE TABLE "deviceHub".printer ("printNodeId" integer NOT NULL,
                                                        "computerId" integer NOT NULL,
                                                                             name text NOT NULL,
                                                                                       description text, state text NOT NULL,
                                                                                                                    bins jsonb,
                                                                                                                    "collate" boolean, copies integer, color boolean, dpis jsonb,
                                                                                                                                                                      extent jsonb,
                                                                                                                                                                             medias jsonb,
                                                                                                                                                                             nup jsonb,
                                                                                                                                                                             papers jsonb,
                                                                                                                                                                             printrate jsonb,
                                                                                                                                                                             supports_custom_paper_size boolean, duplex boolean, "printerType" text);


CREATE TABLE "deviceHub"."printerType" (type text NOT NULL);


CREATE TABLE "deviceHub".scale ("deviceName" text NOT NULL,
                                                  "deviceNum" integer NOT NULL,
                                                                      "computerId" integer NOT NULL,
                                                                                           vendor text, "vendorId" integer, "productId" integer, port text, count integer, measurement jsonb,
                                                                                                                                                                           "ntpOffset" integer, "ageOfData" integer, "stationId" integer, active boolean DEFAULT true,
                                                                                                                                                                                                                                                                 id integer DEFAULT public.defaultid('deviceHub'::text, 'scale'::text, 'id'::text) NOT NULL);


CREATE TABLE editor.block (id integer DEFAULT public.defaultid('editor'::text, 'block'::text, 'id'::text) NOT NULL,
                                                                                                          name text NOT NULL,
                                                                                                                    path text NOT NULL,
                                                                                                                              assets jsonb,
                                                                                                                              "fileId" integer NOT NULL,
                                                                                                                                               category text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                          updated_at timestamp with time zone DEFAULT now());


CREATE TABLE editor."cssFileLinks" ("guiFileId" integer NOT NULL,
                                                        "cssFileId" integer NOT NULL,
                                                                            "position" bigint, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                           updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                       id integer DEFAULT public.defaultid('editor'::text, 'cssFileLinks'::text, 'id'::text) NOT NULL);


CREATE TABLE editor.file (id integer DEFAULT public.defaultid('editor'::text, 'file'::text, 'id'::text) NOT NULL,
                                                                                                        path text NOT NULL,
                                                                                                                  created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                    updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                      "fileType" text, commits jsonb,
                                                                                                                                                                                                                                       "lastSaved" timestamp with time zone,
                                                                                                                                                                                                                                                                       "fileName" text, "isTemplate" boolean, "isBlock" boolean);


CREATE TABLE editor."jsFileLinks" ("guiFileId" integer NOT NULL,
                                                       "jsFileId" integer NOT NULL,
                                                                          "position" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                          updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                      id integer DEFAULT public.defaultid('editor'::text, 'jsFileLinks'::text, 'id'::text) NOT NULL);


CREATE TABLE editor."linkedFiles" (id integer NOT NULL,
                                              records jsonb);


CREATE TABLE editor.template (id integer DEFAULT public.defaultid('editor'::text, 'template'::text, 'id'::text) NOT NULL,
                                                                                                                name text NOT NULL,
                                                                                                                          route text NOT NULL,
                                                                                                                                     type text, thumbnail text);


CREATE TABLE fulfilment.brand_recurrence ("brandId" integer NOT NULL,
                                                            "recurrenceId" integer NOT NULL,
                                                                                   "isActive" boolean DEFAULT true NOT NULL);


CREATE TABLE fulfilment.charge (id integer DEFAULT public.defaultid('fulfilment'::text, 'charge'::text, 'id'::text) NOT NULL,
                                                                                                                    "orderValueFrom" numeric NOT NULL,
                                                                                                                                             "orderValueUpto" numeric NOT NULL,
                                                                                                                                                                      charge numeric NOT NULL,
                                                                                                                                                                                     "mileRangeId" integer, "autoDeliverySelection" boolean DEFAULT true NOT NULL);


CREATE TABLE fulfilment."deliveryPreferenceByCharge" ("chargeId" integer NOT NULL,
                                                                         "clauseId" integer NOT NULL,
                                                                                            "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                            priority integer NOT NULL,
                                                                                                                                             created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                         updated_at timestamp with time zone DEFAULT now());


CREATE TABLE fulfilment."deliveryService" (id integer DEFAULT public.defaultid('fulfilment'::text, 'deliveryService'::text, 'id'::text) NOT NULL,
                                                                                                                                        "partnershipId" integer, "isThirdParty" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                     "isActive" boolean DEFAULT false,
                                                                                                                                                                                                                                "companyName" text NOT NULL,
                                                                                                                                                                                                                                                   logo text);


CREATE TABLE fulfilment."fulfillmentType" (value text NOT NULL,
                                                      "isActive" boolean DEFAULT true NOT NULL);


CREATE TABLE fulfilment.recurrence (id integer DEFAULT public.defaultid('fulfilment'::text, 'recurrence'::text, 'id'::text) NOT NULL,
                                                                                                                            rrule text NOT NULL,
                                                                                                                                       type text DEFAULT 'PREORDER_DELIVERY'::text NOT NULL,
                                                                                                                                                                                   "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                   psql_rrule jsonb);


CREATE TABLE imports.import (id integer DEFAULT public.defaultid('imports'::text, 'import'::text, 'id'::text) NOT NULL,
                                                                                                              entity text NOT NULL,
                                                                                                                          file text NOT NULL,
                                                                                                                                    "importType" text NOT NULL,
                                                                                                                                                      confirm boolean DEFAULT false NOT NULL,
                                                                                                                                                                                    created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                status text);


CREATE TABLE imports."importHistory" (id integer DEFAULT public.defaultid('imports'::text, 'importHistory'::text, 'id'::text) NOT NULL,
                                                                                                                              "importId" integer, "importFrom" text);


CREATE TABLE ingredient."ingredientProcessing" (id integer DEFAULT public.defaultid('ingredient'::text, 'ingredientProcessing'::text, 'id'::text) NOT NULL,
                                                                                                                                                  "processingName" text NOT NULL,
                                                                                                                                                                        "ingredientId" integer NOT NULL,
                                                                                                                                                                                               "nutritionalInfo" jsonb,
                                                                                                                                                                                               cost jsonb,
                                                                                                                                                                                               created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                           updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                       "isArchived" boolean DEFAULT false NOT NULL);


CREATE TABLE ingredient."ingredientSacahet_recipeHubSachet" ("ingredientSachetId" integer NOT NULL,
                                                                                          "recipeHubSachetId" uuid NOT NULL);


CREATE TABLE ingredient."modeOfFulfillmentEnum" (value text NOT NULL,
                                                            description text);


CREATE TABLE insights.app_module_insight ("appTitle" text NOT NULL,
                                                          "moduleTitle" text NOT NULL,
                                                                             "insightIdentifier" text NOT NULL);


CREATE TABLE insights.chart (id integer DEFAULT public.defaultid('insights'::text, 'chart'::text, 'id'::text) NOT NULL,
                                                                                                              "layoutType" text DEFAULT 'HERO'::text,
                                                                                                                                        config jsonb,
                                                                                                                                        "insightIdentifier" text NOT NULL);


CREATE TABLE insights.date (date date NOT NULL,
                                      day text);


CREATE TABLE insights.day ("dayName" text NOT NULL,
                                          "dayNumber" integer);


CREATE TABLE insights.hour (hour integer NOT NULL);


CREATE TABLE insights.insights (query text NOT NULL,
                                           "availableOptions" jsonb NOT NULL,
                                                                    switches jsonb NOT NULL,
                                                                                   "isActive" boolean DEFAULT false,
                                                                                                              "defaultOptions" jsonb,
                                                                                                              identifier text NOT NULL,
                                                                                                                              description text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                            updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                        filters jsonb,
                                                                                                                                                                                                                                        config jsonb,
                                                                                                                                                                                                                                        "schemaVariables" jsonb);

COMMENT ON COLUMN insights.insights.filters IS 'same as availableOptions, will be used to render individual options like date range in insights.';


CREATE TABLE insights.month (number integer NOT NULL,
                                            name text NOT NULL);


CREATE TABLE instructions."instructionSet" (id integer DEFAULT public.defaultid('instructions'::text, 'instructionSet'::text, 'id'::text) NOT NULL,
                                                                                                                                          title text, "position" integer, "simpleRecipeId" integer, "simpleRecipeProductOptionId" integer);


CREATE TABLE instructions."instructionStep" (id integer DEFAULT public.defaultid('instructions'::text, 'instructionStep'::text, 'id'::text) NOT NULL,
                                                                                                                                            title text, description text, assets jsonb DEFAULT jsonb_build_object('images', '[]'::jsonb, 'videos', '[]'::jsonb) NOT NULL,
                                                                                                                                                                                                                                                                "position" integer, "instructionSetId" integer NOT NULL,
                                                                                                                                                                                                                                                                                                               "isVisible" boolean DEFAULT true NOT NULL);


CREATE TABLE inventory."bulkItem" (id integer DEFAULT public.defaultid('inventory'::text, 'bulkItem'::text, 'id'::text) NOT NULL,
                                                                                                                        "processingName" text NOT NULL,
                                                                                                                                              "supplierItemId" integer NOT NULL,
                                                                                                                                                                       labor jsonb,
                                                                                                                                                                       "shelfLife" jsonb,
                                                                                                                                                                       yield jsonb,
                                                                                                                                                                       "nutritionInfo" jsonb,
                                                                                                                                                                       sop jsonb,
                                                                                                                                                                       allergens jsonb,
                                                                                                                                                                       "parLevel" numeric, "maxLevel" numeric, "onHand" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                          "storageCondition" jsonb,
                                                                                                                                                                                                                                          "createdAt" timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                       "updatedAt" timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                    "bulkDensity" numeric DEFAULT 1,
                                                                                                                                                                                                                                                                                                                                                                  equipments jsonb,
                                                                                                                                                                                                                                                                                                                                                                  unit text, committed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                         awaiting numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                    consumed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                               "isAvailable" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     image jsonb);


CREATE TABLE inventory."bulkItemHistory" (id integer DEFAULT public.defaultid('inventory'::text, 'bulkItemHistory'::text, 'id'::text) NOT NULL,
                                                                                                                                      "bulkItemId" integer NOT NULL,
                                                                                                                                                           quantity numeric NOT NULL,
                                                                                                                                                                            comment jsonb,
                                                                                                                                                                                    "purchaseOrderItemId" integer, "bulkWorkOrderId" integer, status text NOT NULL,
                                                                                                                                                                                                                                                          unit text, "orderSachetId" integer, "sachetWorkOrderId" integer, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                       updated_at timestamp with time zone DEFAULT now());


CREATE TABLE inventory."bulkItem_unitConversion" (id integer DEFAULT public.defaultid('inventory'::text, 'bulkItem_unitConversion'::text, 'id'::text) NOT NULL,
                                                                                                                                                      "entityId" integer NOT NULL,
                                                                                                                                                                         "unitConversionId" integer NOT NULL);


CREATE TABLE inventory."bulkWorkOrder" (id integer DEFAULT public.defaultid('inventory'::text, 'bulkWorkOrder'::text, 'id'::text) NOT NULL,
                                                                                                                                  "inputBulkItemId" integer, "outputBulkItemId" integer, "outputQuantity" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                            "userId" integer, "scheduledOn" timestamp with time zone,
                                                                                                                                                                                                                                                                                "inputQuantity" numeric, status text DEFAULT 'UNPUBLISHED'::text,
                                                                                                                                                                                                                                                                                                                             "stationId" integer, "inputQuantityUnit" text, "supplierItemId" integer, "isPublished" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                          name text, "outputYield" numeric);


CREATE TABLE inventory."packagingHistory" (id integer DEFAULT public.defaultid('inventory'::text, 'packagingHistory'::text, 'id'::text) NOT NULL,
                                                                                                                                        "packagingId" integer NOT NULL,
                                                                                                                                                              quantity numeric NOT NULL,
                                                                                                                                                                               "purchaseOrderItemId" integer NOT NULL,
                                                                                                                                                                                                             status text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                                                                                                 unit text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                        updated_at timestamp with time zone DEFAULT now());


CREATE TABLE inventory."purchaseOrderItem" (id integer DEFAULT public.defaultid('inventory'::text, 'purchaseOrderItem'::text, 'id'::text) NOT NULL,
                                                                                                                                          "bulkItemId" integer, "supplierItemId" integer, "orderQuantity" numeric DEFAULT 0,
                                                                                                                                                                                                                          status text DEFAULT 'UNPUBLISHED'::text NOT NULL,
                                                                                                                                                                                                                                                                  details jsonb,
                                                                                                                                                                                                                                                                  unit text, "supplierId" integer, price numeric, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                              updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                          "packagingId" integer, "mandiPurchaseOrderItemId" integer, type text DEFAULT 'PACKAGING'::text NOT NULL);


CREATE TABLE inventory."sachetItem" (id integer DEFAULT public.defaultid('inventory'::text, 'sachetItem'::text, 'id'::text) NOT NULL,
                                                                                                                            "unitSize" numeric NOT NULL,
                                                                                                                                               "parLevel" numeric, "maxLevel" numeric, "onHand" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                  "isAvailable" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                     "bulkItemId" integer NOT NULL,
                                                                                                                                                                                                                                                                          unit text NOT NULL,
                                                                                                                                                                                                                                                                                    consumed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                               awaiting numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                          committed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                      "isArchived" boolean DEFAULT false NOT NULL);


CREATE TABLE inventory."sachetItemHistory" (id integer DEFAULT public.defaultid('inventory'::text, 'sachetItemHistory'::text, 'id'::text) NOT NULL,
                                                                                                                                          "sachetItemId" integer NOT NULL,
                                                                                                                                                                 "sachetWorkOrderId" integer, quantity numeric NOT NULL,
                                                                                                                                                                                                               comment jsonb,
                                                                                                                                                                                                                       status text NOT NULL,
                                                                                                                                                                                                                                   "orderSachetId" integer, unit text, created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                   updated_at timestamp with time zone DEFAULT now());


CREATE TABLE inventory."sachetWorkOrder" (id integer DEFAULT public.defaultid('inventory'::text, 'sachetWorkOrder'::text, 'id'::text) NOT NULL,
                                                                                                                                      "inputBulkItemId" integer, "outputSachetItemId" integer, "outputQuantity" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                  "inputQuantity" numeric, "packagingId" integer, label jsonb,
                                                                                                                                                                                                                                                                                  "stationId" integer, "userId" integer, "scheduledOn" timestamp with time zone,
                                                                                                                                                                                                                                                                                                                                                           status text DEFAULT 'UNPUBLISHED'::text,
                                                                                                                                                                                                                                                                                                                                                                               created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                           updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                       name text, "supplierItemId" integer, "isPublished" boolean DEFAULT false NOT NULL);


CREATE TABLE inventory.supplier (id integer DEFAULT public.defaultid('inventory'::text, 'supplier'::text, 'id'::text) NOT NULL,
                                                                                                                      name text NOT NULL,
                                                                                                                                "contactPerson" jsonb,
                                                                                                                                address jsonb,
                                                                                                                                "shippingTerms" jsonb,
                                                                                                                                "paymentTerms" jsonb,
                                                                                                                                available boolean DEFAULT true NOT NULL,
                                                                                                                                                               "importId" integer, "mandiSupplierId" integer, logo jsonb);


CREATE TABLE inventory."supplierItem_unitConversion" (id integer DEFAULT public.defaultid('inventory'::text, 'supplierItem_unitConversion'::text, 'id'::text) NOT NULL,
                                                                                                                                                              "entityId" integer NOT NULL,
                                                                                                                                                                                 "unitConversionId" integer NOT NULL);


CREATE TABLE inventory."unitConversionByBulkItem" ("bulkItemId" integer NOT NULL,
                                                                        "unitConversionId" integer NOT NULL,
                                                                                                   "customConversionFactor" numeric NOT NULL,
                                                                                                                                    id integer DEFAULT public.defaultid('inventory'::text, 'unitConversionByBulkItem'::text, 'id'::text) NOT NULL);


CREATE TABLE master."accompanimentType" (id integer DEFAULT public.defaultid('master'::text, 'accompanimentType'::text, 'id'::text) NOT NULL,
                                                                                                                                    name text NOT NULL);


CREATE TABLE master."allergenName" (id integer DEFAULT public.defaultid('master'::text, 'allergenName'::text, 'id'::text) NOT NULL,
                                                                                                                          name text NOT NULL,
                                                                                                                                    description text);


CREATE TABLE master."cuisineName" (name text NOT NULL,
                                             id integer DEFAULT public.defaultid('master'::text, 'cuisineName'::text, 'id'::text) NOT NULL);


CREATE TABLE master."processingName" (id integer DEFAULT public.defaultid('master'::text, 'processingName'::text, 'id'::text) NOT NULL,
                                                                                                                              name text NOT NULL,
                                                                                                                                        description text);


CREATE TABLE master."productCategory" (name text NOT NULL,
                                                 "imageUrl" text, "iconUrl" text, "metaDetails" jsonb,
                                                                                  "importHistoryId" integer);


CREATE TABLE master.unit (id integer DEFAULT public.defaultid('master'::text, 'unit'::text, 'id'::text) NOT NULL,
                                                                                                        name text NOT NULL);


CREATE TABLE master."unitConversion" (id integer DEFAULT public.defaultid('master'::text, 'unitConversion'::text, 'id'::text) NOT NULL,
                                                                                                                              "inputUnitName" text NOT NULL,
                                                                                                                                                   "outputUnitName" text NOT NULL,
                                                                                                                                                                         "conversionFactor" numeric NOT NULL,
                                                                                                                                                                                                    "bulkDensity" numeric, "isCanonical" boolean DEFAULT false);

COMMENT ON COLUMN master."unitConversion"."bulkDensity" IS 'kg/l';

COMMENT ON COLUMN master."unitConversion"."isCanonical" IS 'is standard?';


CREATE TABLE notifications."displayNotification" (id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                           "typeId" uuid NOT NULL,
                                                                                                         created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                           updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                             content jsonb NOT NULL,
                                                                                                                                                                                                                           seen boolean DEFAULT false NOT NULL);


CREATE TABLE notifications."emailConfig" (id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                   "typeId" uuid NOT NULL,
                                                                                                 template jsonb,
                                                                                                          email text NOT NULL,
                                                                                                                     "isActive" boolean DEFAULT true NOT NULL);


CREATE TABLE notifications."printConfig" (id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                   "printerPrintNodeId" integer, "typeId" uuid NOT NULL,
                                                                                                                               "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                               created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                 updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                   template jsonb NOT NULL);


CREATE TABLE notifications."smsConfig" (id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                                 "typeId" uuid NOT NULL,
                                                                                               template jsonb,
                                                                                                        "phoneNo" text NOT NULL,
                                                                                                                       "isActive" boolean DEFAULT true NOT NULL);


CREATE TABLE notifications.type (id uuid DEFAULT public.gen_random_uuid() NOT NULL,
                                                                          name text NOT NULL,
                                                                                    description text, app text NOT NULL,
                                                                                                               "table" text NOT NULL,
                                                                                                                            schema text NOT NULL,
                                                                                                                                        op text NOT NULL,
                                                                                                                                                fields jsonb NOT NULL,
                                                                                                                                                             "isActive" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                              template jsonb NOT NULL,
                                                                                                                                                                                                             "isLocal" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                            "isGlobal" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                                            "playAudio" boolean DEFAULT false,
                                                                                                                                                                                                                                                                                                        "audioUrl" text, "webhookEnv" text DEFAULT 'WEBHOOK_DEFAULT_NOTIFICATION_HANDLER'::text,
                                                                                                                                                                                                                                                                                                                                                   "emailFrom" jsonb DEFAULT '{"name": "", "email": ""}'::jsonb);


CREATE TABLE "onDemand".brand_collection ("brandId" integer NOT NULL,
                                                            "collectionId" integer NOT NULL,
                                                                                   "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                   "importHistoryId" integer);


CREATE TABLE "onDemand".category (name text NOT NULL,
                                            id integer DEFAULT public.defaultid('onDemand'::text, 'category'::text, 'id'::text) NOT NULL);


CREATE TABLE "onDemand".collection (id integer DEFAULT public.defaultid('onDemand'::text, 'collection'::text, 'id'::text) NOT NULL,
                                                                                                                          name text, "startTime" time without time zone,
                                                                                                                                                                   "endTime" time without time zone,
                                                                                                                                                                                               rrule jsonb,
                                                                                                                                                                                               created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                           updated_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                       "importHistoryId" integer);


CREATE TABLE "onDemand"."collection_productCategory" (id integer DEFAULT public.defaultid('onDemand'::text, 'collection_productCategory'::text, 'id'::text) NOT NULL,
                                                                                                                                                            "collectionId" integer NOT NULL,
                                                                                                                                                                                   "productCategoryName" text NOT NULL,
                                                                                                                                                                                                              "position" numeric, "importHistoryId" integer);


CREATE TABLE "onDemand".modifier (id integer DEFAULT public.defaultid('onDemand'::text, 'modifier'::text, 'id'::text) NOT NULL,
                                                                                                                      name text NOT NULL,
                                                                                                                                "importHistoryId" integer, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                             updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE "onDemand"."modifierCategory" (id integer DEFAULT public.defaultid('onDemand'::text, 'modifierCategory'::text, 'id'::text) NOT NULL,
                                                                                                                                        name text NOT NULL,
                                                                                                                                                  type text DEFAULT 'single'::text NOT NULL,
                                                                                                                                                                                   "isVisible" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                    "isRequired" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                      limits jsonb DEFAULT '{"max": null, "min": 1}'::jsonb,
                                                                                                                                                                                                                                                                           "modifierTemplateId" integer NOT NULL,
                                                                                                                                                                                                                                                                                                        created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                          updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE "order"."cartItem" (id integer DEFAULT public.defaultid('order'::text, 'cartItem'::text, 'id'::text) NOT NULL,
                                                                                                                  "cartId" integer, "parentCartItemId" integer, "isModifier" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                   "productId" integer, "productOptionId" integer, "comboProductComponentId" integer, "customizableProductComponentId" integer, "simpleRecipeYieldId" integer, "sachetItemId" integer, "isAssembled" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                           "unitPrice" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                         "refundPrice" numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         "stationId" integer, "labelTemplateId" integer, "packagingId" integer, "instructionCardTemplateId" integer, "assemblyStatus" text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   "position" numeric, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "isLabelled" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              "isPortioned" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  accuracy numeric DEFAULT 5,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "ingredientSachetId" integer, "isAddOn" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         "addOnLabel" text, "addOnPrice" numeric, "isAutoAdded" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      "inventoryProductBundleId" integer, "subscriptionOccurenceProductId" integer, "subscriptionOccurenceAddOnProductId" integer, "packingStatus" text DEFAULT 'PENDING'::text NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                "modifierOptionId" integer, "subRecipeYieldId" integer, status text DEFAULT 'PENDING'::text NOT NULL);


CREATE TABLE products."productOptionType" (title text NOT NULL,
                                                      description text, "orderMode" text NOT NULL);


CREATE TABLE "simpleRecipe"."simpleRecipeComponent_productOptionType" ("simpleRecipeComponentId" integer NOT NULL,
                                                                                                         "productOptionType" text NOT NULL,
                                                                                                                                  "orderMode" text NOT NULL);


CREATE TABLE "simpleRecipe"."simpleRecipeYield_ingredientSachet" ("recipeYieldId" integer NOT NULL,
                                                                                          "ingredientSachetId" integer, "isVisible" boolean DEFAULT true NOT NULL,
                                                                                                                                                         "slipName" text, "isSachetValid" boolean, "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                      "simpleRecipeIngredientProcessingId" integer NOT NULL,
                                                                                                                                                                                                                                                                                   "subRecipeYieldId" integer, "simpleRecipeId" integer);


CREATE TABLE "simpleRecipe"."simpleRecipe_productOptionType" ("simpleRecipeId" integer NOT NULL,
                                                                                       "productOptionTypeTitle" text NOT NULL,
                                                                                                                     "orderMode" text NOT NULL);


CREATE TABLE "order".cart_rewards (id integer NOT NULL,
                                              "cartId" integer NOT NULL,
                                                               "rewardId" integer NOT NULL);


CREATE TABLE "order"."orderMode" (title text NOT NULL,
                                             description text, assets jsonb,
                                                               "validWhen" text);


CREATE TABLE "order"."orderStatusEnum" (value text NOT NULL,
                                                   description text NOT NULL,
                                                                    index integer, title text);


CREATE TABLE "order"."thirdPartyOrder" (source text NOT NULL,
                                                    "thirdPartyOrderId" text NOT NULL,
                                                                             "parsedData" jsonb DEFAULT '{}'::jsonb,
                                                                                                        id integer DEFAULT public.defaultid('order'::text, 'thirdPartyOrder'::text, 'id'::text) NOT NULL);


CREATE TABLE packaging.packaging (id integer DEFAULT public.defaultid('packaging'::text, 'packaging'::text, 'id'::text) NOT NULL,
                                                                                                                        name text NOT NULL,
                                                                                                                                  "packagingSku" text, "supplierId" integer, "unitPrice" numeric, "parLevel" integer, "maxLevel" integer, "onHand" integer DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                     "unitQuantity" numeric, "caseQuantity" numeric, "minOrderValue" numeric, "leadTime" jsonb,
                                                                                                                                                                                                                                                                                                                                              "isAvailable" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                  type text, awaiting numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                        committed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                    consumed numeric DEFAULT 0 NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                               assets jsonb,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                               "mandiPackagingId" integer, length numeric, width numeric, height numeric, gusset numeric, thickness numeric, "LWHUnit" text DEFAULT 'mm'::text,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    "loadCapacity" numeric, "loadVolume" numeric, "packagingSpecificationsId" integer NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      weight numeric);


CREATE TABLE packaging."packagingSpecifications" (id integer DEFAULT public.defaultid('packaging'::text, 'packagingSpecifications'::text, 'id'::text) NOT NULL,
                                                                                                                                                      "innerWaterResistant" boolean, "outerWaterResistant" boolean, "innerGreaseResistant" boolean, "outerGreaseResistant" boolean, microwaveable boolean, "maxTemperatureInFahrenheit" boolean, recyclable boolean, compostable boolean, recycled boolean, "fdaCompliant" boolean, compressibility boolean, opacity text, "mandiPackagingId" integer, "packagingMaterial" text);


CREATE TABLE products."inventoryProductBundle" (id integer DEFAULT public.defaultid('products'::text, 'inventoryProductBundle'::text, 'id'::text) NOT NULL,
                                                                                                                                                  label text NOT NULL);


CREATE TABLE products."inventoryProductBundleSachet" (id integer DEFAULT public.defaultid('products'::text, 'inventoryProductBundleSachet'::text, 'id'::text) NOT NULL,
                                                                                                                                                              "inventoryProductBundleId" integer NOT NULL,
                                                                                                                                                                                                 "supplierItemId" integer, "sachetItemId" integer, "bulkItemId" integer, "bulkItemQuantity" numeric);


CREATE TABLE products."productConfigTemplate" (id integer DEFAULT public.defaultid('products'::text, 'productConfigTemplate'::text, 'id'::text) NOT NULL,
                                                                                                                                                template jsonb NOT NULL,
                                                                                                                                                               "isDefault" boolean, "isMandatory" boolean);


CREATE TABLE products."productDataConfig" ("productId" integer NOT NULL,
                                                               "productConfigTemplateId" integer NOT NULL,
                                                                                                 data jsonb NOT NULL);


CREATE TABLE products."productType" (title text NOT NULL,
                                                "displayName" text NOT NULL);


CREATE TABLE safety."safetyCheck" (id integer DEFAULT public.defaultid('safety'::text, 'safetyCheck'::text, 'id'::text) NOT NULL,
                                                                                                                        created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                          updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                            "isVisibleOnStore" boolean NOT NULL);


CREATE TABLE safety."safetyCheckPerUser" (id integer DEFAULT public.defaultid('safety'::text, 'safetyCheckPerUser'::text, 'id'::text) NOT NULL,
                                                                                                                                      "SafetyCheckId" integer NOT NULL,
                                                                                                                                                              "userId" integer NOT NULL,
                                                                                                                                                                               "usesMask" boolean NOT NULL,
                                                                                                                                                                                                  "usesSanitizer" boolean NOT NULL,
                                                                                                                                                                                                                          created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                            temperature numeric);


CREATE TABLE settings.app (id integer DEFAULT public.defaultid('settings'::text, 'app'::text, 'id'::text) NOT NULL,
                                                                                                          title text NOT NULL,
                                                                                                                     created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                       updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                         icon text, route text);


CREATE TABLE settings."appPermission" (id integer DEFAULT public.defaultid('settings'::text, 'appPermission'::text, 'id'::text) NOT NULL,
                                                                                                                                "appId" integer NOT NULL,
                                                                                                                                                route text NOT NULL,
                                                                                                                                                           title text NOT NULL,
                                                                                                                                                                      "fallbackMessage" text);


CREATE TABLE settings."appSettings" (id integer DEFAULT public.defaultid('settings'::text, 'appSettings'::text, 'id'::text) NOT NULL,
                                                                                                                            app text NOT NULL,
                                                                                                                                     type text NOT NULL,
                                                                                                                                               identifier text NOT NULL,
                                                                                                                                                               value jsonb NOT NULL);


CREATE TABLE settings.app_module ("appTitle" text NOT NULL,
                                                  "moduleTitle" text NOT NULL);


CREATE TABLE settings."organizationSettings" (title text NOT NULL,
                                                         value text NOT NULL);


CREATE TABLE settings.role (id integer DEFAULT public.defaultid('settings'::text, 'role'::text, 'id'::text) NOT NULL,
                                                                                                            title text NOT NULL,
                                                                                                                       created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                         updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE settings.role_app (id integer DEFAULT public.defaultid('settings'::text, 'role_app'::text, 'id'::text) NOT NULL,
                                                                                                                    "roleId" integer NOT NULL,
                                                                                                                                     "appId" integer NOT NULL,
                                                                                                                                                     created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                       updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE settings."role_appPermission" ("appPermissionId" integer NOT NULL,
                                                                      "role_appId" integer NOT NULL,
                                                                                           value boolean NOT NULL);


CREATE TABLE settings.station (id integer DEFAULT public.defaultid('settings'::text, 'station'::text, 'id'::text) NOT NULL,
                                                                                                                  name text NOT NULL,
                                                                                                                            "defaultLabelPrinterId" integer, "defaultKotPrinterId" integer, "defaultScaleId" integer, "isArchived" boolean DEFAULT false NOT NULL);


CREATE TABLE settings.station_kot_printer ("stationId" integer NOT NULL,
                                                               "printNodeId" integer NOT NULL,
                                                                                     active boolean DEFAULT true NOT NULL);


CREATE TABLE settings.station_label_printer ("stationId" integer NOT NULL,
                                                                 "printNodeId" integer NOT NULL,
                                                                                       active boolean DEFAULT true NOT NULL);


CREATE TABLE settings.station_user ("userKeycloakId" text NOT NULL,
                                                          "stationId" integer NOT NULL,
                                                                              active boolean DEFAULT true NOT NULL);


CREATE TABLE settings."user" (id integer DEFAULT public.defaultid('settings'::text, 'user'::text, 'id'::text) NOT NULL,
                                                                                                              "firstName" text, "lastName" text, email text, "tempPassword" text, "phoneNo" text, "keycloakId" text, "isOwner" boolean DEFAULT false NOT NULL);


CREATE TABLE settings.user_role (id integer DEFAULT public.defaultid('settings'::text, 'user_role'::text, 'id'::text) NOT NULL,
                                                                                                                      "userId" text NOT NULL,
                                                                                                                                    "roleId" integer NOT NULL,
                                                                                                                                                     created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                       updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE "simpleRecipe"."simpleRecipe_ingredient_processing" ("processingId" integer, id integer DEFAULT public.defaultid('simpleRecipe'::text, 'simpleRecipe_ingredient_processing'::text, 'id'::text) NOT NULL,
                                                                                                                                                                                                            "simpleRecipeId" integer, "ingredientId" integer, "position" integer, "isArchived" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                                     "subRecipeId" integer);


CREATE TABLE subscription."brand_subscriptionTitle" ("brandId" integer NOT NULL,
                                                                       "subscriptionTitleId" integer NOT NULL,
                                                                                                     "isActive" boolean DEFAULT true NOT NULL,
                                                                                                                                     "allowAutoSelectOptOut" boolean DEFAULT true NOT NULL);


CREATE TABLE subscription.subscription (id integer DEFAULT public.defaultid('subscription'::text, 'subscription'::text, 'id'::text) NOT NULL,
                                                                                                                                    "subscriptionItemCountId" integer NOT NULL,
                                                                                                                                                                      rrule text NOT NULL,
                                                                                                                                                                                 "metaDetails" jsonb,
                                                                                                                                                                                 "cutOffTime" time without time zone,
                                                                                                                                                                                                                "leadTime" jsonb,
                                                                                                                                                                                                                "startTime" jsonb DEFAULT '{"unit": "days", "value": 28}'::jsonb,
                                                                                                                                                                                                                                          "startDate" date, "endDate" date, "defaultSubscriptionAutoSelectOption" text, "reminderSettings" jsonb DEFAULT '{"template": "Subscription Reminder Email", "hoursBefore": [24]}'::jsonb,
                                                                                                                                                                                                                                                                                                                                                         "subscriptionServingId" integer, "subscriptionTitleId" integer);


CREATE TABLE subscription."subscriptionAutoSelectOption" ("methodName" text NOT NULL,
                                                                            "displayName" text NOT NULL);


CREATE TABLE subscription."subscriptionPickupOption" (id integer DEFAULT public.defaultid('subscription'::text, 'subscriptionPickupOption'::text, 'id'::text) NOT NULL,
                                                                                                                                                              "time" jsonb DEFAULT '{"to": "", "from": ""}'::jsonb NOT NULL,
                                                                                                                                                                                                                   address jsonb DEFAULT '{"lat": "", "lng": "", "city": "", "label": "", "line1": "", "line2": "", "notes": "", "state": "", "country": "", "zipcode": ""}'::jsonb NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                    created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                                                                                                                                                                                                      updated_at timestamp with time zone DEFAULT now() NOT NULL);


CREATE TABLE subscription.subscription_zipcode ("subscriptionId" integer NOT NULL,
                                                                         zipcode text NOT NULL,
                                                                                      "deliveryPrice" numeric DEFAULT 0 NOT NULL,
                                                                                                                        "isActive" boolean DEFAULT true,
                                                                                                                                                   "deliveryTime" jsonb DEFAULT '{"to": "", "from": ""}'::jsonb,
                                                                                                                                                                                "subscriptionPickupOptionId" integer, "isDeliveryActive" boolean DEFAULT true NOT NULL,
                                                                                                                                                                                                                                                              "isPickupActive" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                                     "defaultAutoSelectFulfillmentMode" text DEFAULT 'DELIVERY'::text NOT NULL);


CREATE TABLE website."navigationMenu" (id integer DEFAULT public.defaultid('website'::text, 'navigationMenu'::text, 'id'::text) NOT NULL,
                                                                                                                                title text NOT NULL,
                                                                                                                                           "isPublished" boolean DEFAULT false NOT NULL);


CREATE TABLE website."navigationMenuItem" (id integer DEFAULT public.defaultid('website'::text, 'navigationMenuItem'::text, 'id'::text) NOT NULL,
                                                                                                                                        label text NOT NULL,
                                                                                                                                                   "navigationMenuId" integer, "parentNavigationMenuItemId" integer, url text, "position" numeric, "openInNewTab" boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                                                                                        created_at timestamp with time zone DEFAULT now(),
                                                                                                                                                                                                                                                                                                                                    updated_at timestamp with time zone DEFAULT now());


CREATE TABLE website.website (id integer DEFAULT public.defaultid('website'::text, 'website'::text, 'id'::text) NOT NULL,
                                                                                                                "brandId" integer NOT NULL,
                                                                                                                                  "faviconUrl" text, created_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                       updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                                                                                                                                                                                                                                         published boolean DEFAULT false NOT NULL);


CREATE TABLE website."websitePage" (id integer DEFAULT public.defaultid('website'::text, 'websitePage'::text, 'id'::text) NOT NULL,
                                                                                                                          "websiteId" integer NOT NULL,
                                                                                                                                              route text NOT NULL,
                                                                                                                                                         "internalPageName" text NOT NULL,
                                                                                                                                                                                 published boolean DEFAULT false NOT NULL,
                                                                                                                                                                                                                 "isArchived" boolean DEFAULT false NOT NULL);


CREATE TABLE website."websitePageModule" (id integer DEFAULT public.defaultid('website'::text, 'websitePageModule'::text, 'id'::text) NOT NULL,
                                                                                                                                      "websitePageId" integer NOT NULL,
                                                                                                                                                              "moduleType" text NOT NULL,
                                                                                                                                                                                "fileId" integer, "internalModuleIdentifier" text, "templateId" integer, "position" numeric, "visibilityConditionId" integer, config jsonb,
                                                                                                                                                                                                                                                                                                              config2 json,
                                                                                                                                                                                                                                                                                                              config3 jsonb,
                                                                                                                                                                                                                                                                                                              config4 text);

