CREATE TABLE "order".cart_rewards (
    id integer DEFAULT public.defaultid(
        'order' :: text,
        'cart_rewards' :: text,
        'id' :: text
    ) NOT NULL,
    "cartId" integer NOT NULL,
    "rewardId" integer NOT NULL
);

CREATE TABLE "order"."orderMode" (
    title text NOT NULL,
    description text,
    assets jsonb,
    "validWhen" text
);

CREATE TABLE "order"."orderStatusEnum" (
    value text NOT NULL,
    description text NOT NULL,
    index integer,
    title text
);

CREATE TABLE "order"."stripePaymentHistory" (
    id integer DEFAULT public.defaultid(
        'order' :: text,
        'stripePaymentHistory' :: text,
        'id' :: text
    ) NOT NULL,
    "transactionId" text,
    "stripeInvoiceId" text,
    "transactionRemark" jsonb DEFAULT '{}' :: jsonb,
    "stripeInvoiceDetails" jsonb DEFAULT '{}' :: jsonb,
    type text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "cartId" integer NOT NULL,
    status text
);

CREATE TABLE "order"."thirdPartyOrder" (
    source text NOT NULL,
    "thirdPartyOrderId" text NOT NULL,
    "parsedData" jsonb DEFAULT '{}' :: jsonb,
    id integer DEFAULT public.defaultid(
        'order' :: text,
        'thirdPartyOrder' :: text,
        'id' :: text
    ) NOT NULL
);

CREATE TABLE packaging.packaging (
    id integer DEFAULT public.defaultid(
        'packaging' :: text,
        'packaging' :: text,
        'id' :: text
    ) NOT NULL,
    name text NOT NULL,
    "packagingSku" text,
    "supplierId" integer,
    "unitPrice" numeric,
    "parLevel" integer,
    "maxLevel" integer,
    "onHand" integer DEFAULT 0 NOT NULL,
    "unitQuantity" numeric,
    "caseQuantity" numeric,
    "minOrderValue" numeric,
    "leadTime" jsonb,
    "isAvailable" boolean DEFAULT false NOT NULL,
    type text,
    awaiting numeric DEFAULT 0 NOT NULL,
    committed numeric DEFAULT 0 NOT NULL,
    consumed numeric DEFAULT 0 NOT NULL,
    assets jsonb,
    "mandiPackagingId" integer,
    length numeric,
    width numeric,
    height numeric,
    gusset numeric,
    thickness numeric,
    "LWHUnit" text DEFAULT 'mm' :: text,
    "loadCapacity" numeric,
    "loadVolume" numeric,
    "packagingSpecificationsId" integer NOT NULL,
    weight numeric
);

CREATE TABLE packaging."packagingSpecifications" (
    id integer DEFAULT public.defaultid(
        'packaging' :: text,
        'packagingSpecifications' :: text,
        'id' :: text
    ) NOT NULL,
    "innerWaterResistant" boolean,
    "outerWaterResistant" boolean,
    "innerGreaseResistant" boolean,
    "outerGreaseResistant" boolean,
    microwaveable boolean,
    "maxTemperatureInFahrenheit" boolean,
    recyclable boolean,
    compostable boolean,
    recycled boolean,
    "fdaCompliant" boolean,
    compressibility boolean,
    opacity text,
    "mandiPackagingId" integer,
    "packagingMaterial" text
);

CREATE TABLE products."inventoryProductBundle" (
    id integer DEFAULT public.defaultid(
        'products' :: text,
        'inventoryProductBundle' :: text,
        'id' :: text
    ) NOT NULL,
    label text NOT NULL
);

CREATE TABLE products."inventoryProductBundleSachet" (
    id integer DEFAULT public.defaultid(
        'products' :: text,
        'inventoryProductBundleSachet' :: text,
        'id' :: text
    ) NOT NULL,
    "inventoryProductBundleId" integer NOT NULL,
    "supplierItemId" integer,
    "sachetItemId" integer,
    "bulkItemId" integer,
    "bulkItemQuantity" numeric
);

CREATE TABLE products."productType" (
    title text NOT NULL,
    "displayName" text NOT NULL
);

CREATE TABLE safety."safetyCheck" (
    id integer DEFAULT public.defaultid(
        'safety' :: text,
        'safetyCheck' :: text,
        'id' :: text
    ) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    "isVisibleOnStore" boolean NOT NULL
);

CREATE TABLE safety."safetyCheckPerUser" (
    id integer DEFAULT public.defaultid(
        'safety' :: text,
        'safetyCheckPerUser' :: text,
        'id' :: text
    ) NOT NULL,
    "SafetyCheckId" integer NOT NULL,
    "userId" integer NOT NULL,
    "usesMask" boolean NOT NULL,
    "usesSanitizer" boolean NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    temperature numeric
);

CREATE TABLE settings.app (
    id integer DEFAULT public.defaultid('settings' :: text, 'app' :: text, 'id' :: text) NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    icon text,
    route text
);

CREATE TABLE settings."appPermission" (
    id integer DEFAULT public.defaultid(
        'settings' :: text,
        'appPermission' :: text,
        'id' :: text
    ) NOT NULL,
    "appId" integer NOT NULL,
    route text NOT NULL,
    title text NOT NULL,
    "fallbackMessage" text
);

CREATE TABLE settings."appSettings" (
    id integer DEFAULT public.defaultid(
        'settings' :: text,
        'appSettings' :: text,
        'id' :: text
    ) NOT NULL,
    app text NOT NULL,
    type text NOT NULL,
    identifier text NOT NULL,
    value jsonb NOT NULL
);

CREATE TABLE settings.app_module (
    "appTitle" text NOT NULL,
    "moduleTitle" text NOT NULL
);

CREATE TABLE settings."organizationSettings" (
    title text NOT NULL,
    value text NOT NULL
);

CREATE TABLE settings.role (
    id integer DEFAULT public.defaultid('settings' :: text, 'role' :: text, 'id' :: text) NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE settings.role_app (
    id integer DEFAULT public.defaultid(
        'settings' :: text,
        'role_app' :: text,
        'id' :: text
    ) NOT NULL,
    "roleId" integer NOT NULL,
    "appId" integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE settings."role_appPermission" (
    "appPermissionId" integer NOT NULL,
    "role_appId" integer NOT NULL,
    value boolean NOT NULL
);

CREATE TABLE settings.station (
    id integer DEFAULT public.defaultid(
        'settings' :: text,
        'station' :: text,
        'id' :: text
    ) NOT NULL,
    name text NOT NULL,
    "defaultLabelPrinterId" integer,
    "defaultKotPrinterId" integer,
    "defaultScaleId" integer,
    "isArchived" boolean DEFAULT false NOT NULL
);

CREATE TABLE settings.station_kot_printer (
    "stationId" integer NOT NULL,
    "printNodeId" integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);

CREATE TABLE settings.station_label_printer (
    "stationId" integer NOT NULL,
    "printNodeId" integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);

CREATE TABLE settings.station_user (
    "userKeycloakId" text NOT NULL,
    "stationId" integer NOT NULL,
    active boolean DEFAULT true NOT NULL
);

CREATE TABLE settings."user" (
    id integer DEFAULT public.defaultid('settings' :: text, 'user' :: text, 'id' :: text) NOT NULL,
    "firstName" text,
    "lastName" text,
    email text,
    "tempPassword" text,
    "phoneNo" text,
    "keycloakId" text,
    "isOwner" boolean DEFAULT false NOT NULL
);

CREATE TABLE settings.user_role (
    id integer DEFAULT public.defaultid(
        'settings' :: text,
        'user_role' :: text,
        'id' :: text
    ) NOT NULL,
    "userId" text NOT NULL,
    "roleId" integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE "simpleRecipe"."simpleRecipe_ingredient_processing" (
    "processingId" integer,
    id integer DEFAULT public.defaultid(
        'simpleRecipe' :: text,
        'simpleRecipe_ingredient_processing' :: text,
        'id' :: text
    ) NOT NULL,
    "simpleRecipeId" integer,
    "ingredientId" integer,
    "position" integer,
    "isArchived" boolean DEFAULT false NOT NULL,
    "subRecipeId" integer
);

CREATE TABLE subscription."brand_subscriptionTitle" (
    "brandId" integer NOT NULL,
    "subscriptionTitleId" integer NOT NULL,
    "isActive" boolean DEFAULT true NOT NULL,
    "allowAutoSelectOptOut" boolean DEFAULT true NOT NULL
);

CREATE TABLE subscription.subscription (
    id integer DEFAULT public.defaultid(
        'subscription' :: text,
        'subscription' :: text,
        'id' :: text
    ) NOT NULL,
    "subscriptionItemCountId" integer NOT NULL,
    rrule text NOT NULL,
    "metaDetails" jsonb,
    "cutOffTime" time without time zone,
    "leadTime" jsonb,
    "startTime" jsonb DEFAULT '{"unit": "days", "value": 28}' :: jsonb,
    "startDate" date,
    "endDate" date,
    "defaultSubscriptionAutoSelectOption" text,
    "reminderSettings" jsonb DEFAULT '{"template": "Subscription Reminder Email", "hoursBefore": [24]}' :: jsonb,
    "subscriptionServingId" integer,
    "subscriptionTitleId" integer
);

CREATE TABLE subscription."subscriptionAutoSelectOption" (
    "methodName" text NOT NULL,
    "displayName" text NOT NULL
);

CREATE TABLE subscription."subscriptionPickupOption" (
    id integer DEFAULT public.defaultid(
        'subscription' :: text,
        'subscriptionPickupOption' :: text,
        'id' :: text
    ) NOT NULL,
    "time" jsonb DEFAULT '{"to": "", "from": ""}' :: jsonb NOT NULL,
    address jsonb DEFAULT '{"lat": "", "lng": "", "city": "", "label": "", "line1": "", "line2": "", "notes": "", "state": "", "country": "", "zipcode": ""}' :: jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE subscription.subscription_zipcode (
    "subscriptionId" integer NOT NULL,
    zipcode text NOT NULL,
    "deliveryPrice" numeric DEFAULT 0 NOT NULL,
    "isActive" boolean DEFAULT true,
    "deliveryTime" jsonb DEFAULT '{"to": "", "from": ""}' :: jsonb,
    "subscriptionPickupOptionId" integer,
    "isDeliveryActive" boolean DEFAULT true NOT NULL,
    "isPickupActive" boolean DEFAULT false NOT NULL,
    "defaultAutoSelectFulfillmentMode" text DEFAULT 'DELIVERY' :: text NOT NULL
);

CREATE TABLE website."navigationMenuItem" (
    id integer DEFAULT public.defaultid(
        'website' :: text,
        'navigationMenuItem' :: text,
        'id' :: text
    ) NOT NULL,
    label text NOT NULL,
    "navigationMenuId" integer,
    "parentNavigationMenuItemId" integer,
    url text,
    "position" numeric,
    "openInNewTab" boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE website.website (
    id integer DEFAULT public.defaultid(
        'website' :: text,
        'website' :: text,
        'id' :: text
    ) NOT NULL,
    "brandId" integer NOT NULL,
    "faviconUrl" text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    published boolean DEFAULT false NOT NULL
);

CREATE TABLE website."websitePage" (
    id integer DEFAULT public.defaultid(
        'website' :: text,
        'websitePage' :: text,
        'id' :: text
    ) NOT NULL,
    "websiteId" integer NOT NULL,
    route text NOT NULL,
    "internalPageName" text NOT NULL,
    published boolean DEFAULT false NOT NULL,
    "isArchived" boolean DEFAULT false NOT NULL
);

CREATE TABLE website."websitePageModule" (
    id integer DEFAULT public.defaultid(
        'website' :: text,
        'websitePageModule' :: text,
        'id' :: text
    ) NOT NULL,
    "websitePageId" integer NOT NULL,
    "moduleType" text NOT NULL,
    "fileId" integer,
    "internalModuleIdentifier" text,
    "templateId" integer,
    "position" numeric,
    "visibilityConditionId" integer,
    config jsonb,
    config2 json,
    config3 jsonb,
    config4 text
);