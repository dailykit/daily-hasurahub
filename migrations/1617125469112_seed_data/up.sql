INSERT INTO
    "order"."orderStatusEnum" (
        value,
        description,
        index,
        title
    )
VALUES
    (
        'ORDER_PENDING',
        'pending',
        1,
        'Pending'
    ),
    (
        'ORDER_UNDER_PROCESSING',
        'order is processing',
        2,
        'Under Processing'
    ),
    (
        'ORDER_READY_TO_ASSEMBLE',
        'order is ready to assemble',
        3,
        'Ready to Assemble'
    ),
    (
        'ORDER_READY_TO_DISPATCH',
        'order is ready for delivery',
        4,
        'Ready to Dispatch'
    ),
    (
        'ORDER_OUT_FOR_DELIVERY',
        'order is in transit',
        5,
        'Out for Delivery'
    ),
    (
        'ORDER_DELIVERED',
        'order is delivered',
        6,
        'Order Delivered'
    );

INSERT INTO
    "order"."orderMode" (
        title,
        description,
        assets,
        "validWhen"
    )
VALUES
    (
        'basic',
        NULL,
        NULL,
        'always'
    ),
    (
        'assembledTogether',
        NULL,
        NULL,
        'containsRecipe'
    ),
    (
        'requisition',
        NULL,
        NULL,
        'containsSupplierItem'
    ),
    (
        'workOrderRequisition',
        NULL,
        NULL,
        'sachetItem'
    ),
    (
        'justInTimePortioning',
        NULL,
        NULL,
        'bulkItem'
    ),
    (
        'instruction',
        NULL,
        NULL,
        NULL
    ),
    (
        'cookOrder',
        NULL,
        NULL,
        'recipe'
    ),
    (
        'assembledSeparately',
        NULL,
        NULL,
        'recipe'
    );

INSERT INTO
    products."productType" (title, "displayName")
VALUES
    ('combo', 'Combo'),
    ('simple', 'Simple'),
    ('customizable', 'Customizable');

INSERT INTO
    products."productOptionType" (
        title,
        description,
        "orderMode"
    )
VALUES
    ('Grocery', NULL, 'requisition'),
    (
        'Meal Prep',
        NULL,
        'assembledTogether'
    ),
    (
        'Ready to Cook',
        NULL,
        'assembledSeparately'
    ),
    (
        'Microwave Ready',
        NULL,
        'assembledTogether'
    ),
    (
        'inventory',
        NULL,
        'requisition'
    ),
    (
        'mealKit',
        NULL,
        'assembledSeparately'
    ),
    (
        'readyToEat',
        NULL,
        'cookOrder'
    ),
    (
        'Meal Kit',
        NULL,
        'assembledSeparately'
    );

INSERT INTO
    "deviceHub"."labelTemplate" (id, name)
VALUES
    (1000, 'product_kot1'),
    (1001, 'sachet_kot1'),
    (1002, 'product1'),
    (1003, 'sachet1');

INSERT INTO
    master.unit (id, name)
VALUES
    (1001, 'kg'),
    (1002, 'pcs'),
    (1000, 'gm'),
    (1004, 'pods'),
    (1005, 'litre'),
    (1006, 'ml'),
    (1007, 'gallon'),
    (1008, 'lb'),
    (1009, 'oz'),
    (1010, 'pinch');

INSERT INTO
    master."accompanimentType" (id, name)
VALUES
    (1000, 'Breads'),
    (1001, 'Drinks');

INSERT INTO
    master."allergenName" (id, name, description)
VALUES
    (1000, 'Peanut', NULL);

INSERT INTO
    master."cuisineName" (name, id)
VALUES
    ('American', 1000),
    ('Indian', 1001),
    ('Thai', 1002),
    ('Chinese', 1003),
    ('French', 1004),
    ('Burgers', 1005),
    ('Pizza', 1006),
    ('Italian', 1007),
    ('Continental', 1008),
    ('Seafood', 1009);

INSERT INTO
    master."processingName" (id, name, description)
VALUES
    (1000, 'Raw', NULL),
    (1001, 'Sliced', NULL),
    (1002, 'Chopped', NULL),
    (1003, 'Puree', NULL),
    (1004, 'Boiled', NULL),
    (1005, 'Fried', NULL);

INSERT INTO
    master."productCategory" (
        name,
        "imageUrl",
        "iconUrl",
        "metaDetails",
        "importHistoryId"
    )
VALUES
    (
        'Starters',
        NULL,
        NULL,
        NULL,
        NULL
    ),
    (
        'Main Course',
        NULL,
        NULL,
        NULL,
        NULL
    ),
    (
        'Desserts',
        NULL,
        NULL,
        NULL,
        NULL
    ),
    (
        'Meal Kits',
        NULL,
        NULL,
        NULL,
        NULL
    ),
    (
        'Ready to Eat',
        NULL,
        NULL,
        NULL,
        NULL
    );

--  NOTIFICATIONS
INSERT INTO
    notifications."type" (
        id,
        "name",
        description,
        app,
        "table",
        "schema",
        op,
        fields,
        "isActive",
        "template",
        "isLocal",
        "isGlobal",
        "playAudio",
        "audioUrl",
        "webhookEnv"
    )
VALUES
    (
        '0f8d450e-bfd3-4aeb-bc75-871a49c700ad',
        'Recipe_Created',
        NULL,
        'Recipe',
        'simpleRecipe',
        'simpleRecipe',
        'INSERT',
        '{}',
        false,
        '{"title": "A new Recipe has been created", "description": "Recipe Name: {{new.name}}"}',
        true,
        true,
        true,
        NULL,
        'WEBHOOK_DEFAULT_NOTIFICATION_HANDLER'
    ),
    (
        'd8252226-e96e-42f6-9320-709d282181d7',
        'Order_Created',
        NULL,
        'Order',
        'order',
        'order',
        'INSERT',
        '{}',
        true,
        '{"title": "A new order placed by {{new.deliveryInfo.dropoff.dropoffInfo.customerFirstName}} {{new.deliveryInfo.dropoff.dropoffInfo.customerLastName}}.", "action": {"url": "/apps/order/orders/{{new.id}}"}, "description": "Order Id: {{new.id}} of amount {{new.currency}}{{new.itemTotal}}."}',
        true,
        true,
        false,
        'https://dailykit-100-gdbro.s3.us-east-2.amazonaws.com/sounds/beep.mp3',
        'WEBHOOK_DEFAULT_NOTIFICATION_HANDLER'
    ),
    (
        '9ed3841a-bf97-496a-bb23-fcb33c63c40b',
        'Recipe_Updated',
        NULL,
        'Recipe',
        'simpleRecipe',
        'simpleRecipe',
        'UPDATE',
        '{"columns": ["name", "cuisine"]}',
        false,
        '{"title": "A new Recipe has been updated", "action": {"url": "/recipe/recipes/{{new.id}}"}, "description": "Recipe Old Name: {{old.name}} {{old.cuisine}} , Recipe New Name: {{new.name}} {{new.cuisine}} "}',
        true,
        true,
        false,
        NULL,
        'WEBHOOK_DEFAULT_NOTIFICATION_HANDLER'
    );

-- FULFILMENT TYPE
INSERT INTO
    fulfilment."fulfillmentType" (value, "isActive")
VALUES
    ('ONDEMAND_DELIVERY', true),
    ('ONDEMAND_PICKUP', true),
    ('PREORDER_PICKUP', true),
    ('PREORDER_DELIVERY', true);

-- DEVICE HUB
INSERT INTO
    "deviceHub"."printerType" ("type")
VALUES
    ('LABEL_PRINTER'),
    ('RECEIPT_PRINTER'),
    ('OTHER_PRINTER'),
    ('KOT_PRINTER');

-- MODE OF FULFILLMENT
INSERT INTO
    ingredient."modeOfFulfillmentEnum" (value, description)
VALUES
    ('realTime', 'realm time'),
    ('plannedLot', 'planned lot');

-- DELIVER SERVICE
INSERT INTO
    fulfilment."deliveryService" (
        "isThirdParty",
        "isActive",
        "companyName"
    )
VALUES
    (false, true, 'Self');

-- BRAND SETTING
INSERT INTO
    brands."brand" (
        "title",
        "isDefault",
        "isPublished",
        "onDemandRequested",
        "subscriptionRequested"
    )
VALUES
    ('Default', true, true, true, true);

-- SUBSCRIPTION STORE BRAND SETTINGS
INSERT INTO
    brands."subscriptionStoreSetting" (id, type, identifier)
VALUES
    (1000, 'Visual', 'priceDisplay'),
    (1001, 'Visual', 'theme-color'),
    (1002, 'brand', 'theme-brand'),
    (1003, 'conventions', 'primary-labels'),
    (1004, 'conventions', 'steps-labels'),
    (1005, 'Select-Plan', 'subscription-metadetails'),
    (1006, 'Select-Plan', 'select-plan-header'),
    (1007, 'Register', 'register-background'),
    (
        1008,
        'Select-Delivery',
        'select-delivery-background'
    ),
    (1009, 'Select-Delivery', 'address'),
    (1010, 'Select-Delivery', 'delivery-day'),
    (1011, 'Select-Delivery', 'first-delivery'),
    (1012, 'Select-Menu', 'select-menu-header'),
    (1013, 'availability', 'Location'),
    (1014, 'brand', 'Contact'),
    (1015, 'rewards', 'Wallet'),
    (1016, 'rewards', 'Loyalty Points'),
    (1017, 'rewards', 'Coupons'),
    (1018, 'rewards', 'Referral'),
    (1019, 'Email Notification', 'email');

INSERT INTO
    brands."brand_subscriptionStoreSetting" ("brandId", "subscriptionStoreSettingId", value)
VALUES
    (
        1000,
        1000,
        '{"pricePerPlan":{"prefix":"Total Price","suffix":"per week","isVisible":true},"pricePerServing":{"prefix":"Starting  From","suffix":"per serving","isVisible":true}}'
    ),
    (
        1000,
        1001,
        '{"accent":"#38a169","highlight":"#0a8acf"}'
    ),
    (
        1000,
        1002,
        '{"logo":{"url":"https://dailykit-133-test.s3.amazonaws.com/images/1594624453166.png","logoMark":"https://dailykit-133-test.s3.amazonaws.com/images/1596121558382.png","wordMark":"https://dailykit-133-test.s3.amazonaws.com/images/1594373838496.png"},"name":"Subscription Shop","favicon":"https://dailykit-133-test.s3.amazonaws.com/images/1592478064798.jpg","metaDescription":"A subscription based food service"}'
    ),
    (
        1000,
        1003,
        '{"login":"Login","logout":"Logout","signup":"Get Started","itemLabel":{"plural":"recipes","singular":"recipe"},"yieldLabel":{"plural":"people","singular":"person"}}'
    ),
    (
        1000,
        1004,
        '{"checkout":"Check Out","register":"Register","selectMenu":"Select Menu","selectDelivery":"Select Delivery"}'
    ),
    (
        1000,
        1005,
        '{"selectButtonLabel":"Select","subscriptionTitle":{"thumbnail":false,"description":false},"subscriptionYield":{"information":"Select one"},"subscriptionItemCount":{"total":true,"perServing":true}}'
    ),
    (
        1000,
        1006,
        '{"background":{"color":"#e0e9e8","image":""}}'
    ),
    (
        1000,
        1007,
        '{"background":{"color":"#e4e4e4","image":"https://dailykit-133-test.s3.amazonaws.com/images/13699-4-3.jpg"}}'
    ),
    (
        1000,
        1008,
        '{"background":{"color":"#e4e4e4","image":"https://dailykit-133-test.s3.amazonaws.com/images/13699-4-3.jpg"}}'
    ),
    (
        1000,
        1009,
        '{"title":"Select Delivery Address","description":"Choose the delivery address you want the food delivered to"}'
    ),
    (
        1000,
        1010,
        '{"title":"Select Delivery Day","description":"Choose the day you the deliveries on"}'
    ),
    (
        1000,
        1011,
        '{"title":"Select First Delivery","description":"Choose first delivery date"}'
    ),
    (
        1000,
        1012,
        '{"background":{"color":"#e4e4e4","image":"https://dailykit-133-test.s3.amazonaws.com/images/13699-4-3.jpg"}}'
    ),
    (
        1000,
        1013,
        '{"lat":"33.8042896","lng":"-118.1709438","city":"Signal Hill","line1":"1700 East Willow Street","line2":"","state":"California","country":"United States","zipcode":"90755"}'
    ),
    (
        1000,
        1014,
        '{"email":"test@dailykit.org","phoneNo":"+13124215900"}'
    ),
    (1000, 1015, '{ "isAvailable": true }'),
    (1000, 1016, '{ "isAvailable": true }'),
    (1000, 1017, '{ "isAvailable": true }'),
    (1000, 1018, '{ "isAvailable": true }'),
    (
        1000,
        1019,
        '{ "name": "Subscription Shop", "email": "no-reply@dailykit.org", "template": { "data": { "id": "{{new.id}}" }, "template": { "name": "subscription", "type": "email", "format": "html" }}}'
    );

--  STORE BRAND SETTING 
INSERT INTO
    brands."storeSetting" (id, type, identifier)
VALUES
    (1, 'brand', 'Brand Logo'),
    (2, 'visual', 'Favicon'),
    (3, 'visual', 'App Title'),
    (4, 'availability', 'Store Availability'),
    (5, 'brand', 'Brand Name'),
    (6, 'availability', 'Pickup Availability'),
    (7, 'availability', 'Delivery Availability'),
    (8, 'visual', 'Primary Color'),
    (9, 'brand', 'Contact'),
    (10, 'availability', 'Location'),
    (11, 'visual', 'Slides'),
    (12, 'sales', 'Food Cost Percent'),
    (13, 'email', 'Email Notification'),
    (14, 'availability', 'Store Live'),
    (15, 'rewards', 'Wallet Availability'),
    (16, 'rewards', 'Loyalty Points Availability'),
    (17, 'rewards', 'Coupons Availability'),
    (18, 'rewards', 'Loyalty Points Usage'),
    (19, 'rewards', 'Referral Availability'),
    (20, 'brand', 'Nav Links'),
    (21, 'brand', 'Terms and Conditions'),
    (22, 'brand', 'Privacy Policy'),
    (23, 'brand', 'Refund Policy'),
    (24, 'app', 'Scripts'),
    (25, 'brand', 'Policy Availability'),
    (26, 'email', 'Order Delivered'),
    (27, 'email', 'Order Cancelled');

INSERT INTO
    brands."brand_storeSetting" ("brandId", "storeSettingId", value)
VALUES
    (
        1000,
        1,
        '{"url":"https://dailykit-133-test.s3.amazonaws.com/images/1596121558382.png"}'
    ),
    (
        1000,
        2,
        '{"url":"https://dailykit-133-test.s3.amazonaws.com/images/1594373838496.png"}'
    ),
    (1000, 3, '{"title":"Test Store"}'),
    (
        1000,
        4,
        '{"to":"23:59","from":"00:01","isOpen":true,"shutMessage":"Will Never Open Again"}'
    ),
    (1000, 5, '{"name":"DailyKIT Store 1"}'),
    (1000, 6, '{"isAvailable":true}'),
    (1000, 7, '{"isAvailable":true}'),
    (1000, 8, '{"color":"#798402"}'),
    (
        1000,
        9,
        '{"email":"test@dailykit.org","phoneNo":"+13124215900"}'
    ),
    (
        1000,
        10,
        '{"lat":"33.8040277","lng":"-118.1700129","city":"Signal Hill","line1":"1798 East Willow Street","line2":"Opp. Blue Bird Store","state":"California","country":"United States","zipcode":"90755"}'
    ),
    (
        1000,
        11,
        '[{"url":"https://images.unsplash.com/photo-1496412705862-e0088f16f791?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&auto=format&fit=crop&w=1050&q=80"},{"url":"https://dailykit-133-test.s3.amazonaws.com/images/13699-4-3.jpg"}]'
    ),
    (1000, 12, '{"lowerLimit":30,"upperLimit":50}'),
    (
        1000,
        13,
        '{"name":"Test","email":"no-reply@dailykit.org","template":{"data":{"id":"{{new.id}}"},"template":{"name":"order_new","type":"email","format":"html"}}}'
    ),
    (
        1000,
        14,
        '{"isStoreLive":false,"isStripeConfigured":true}'
    ),
    (1000, 15, '{ "isAvailable": true }'),
    (1000, 16, '{ "isAvailable": true }'),
    (1000, 17, '{ "isAvailable": true }'),
    (
        1000,
        18,
        '{ "max": 5, "percentage": 50, "converstionRate": 0.5 }'
    ),
    (1000, 19, '{ "isAvailable": false }'),
    (
        1000,
        20,
        '{ "aboutUs": "https://dailykit.org" }'
    ),
    (1000, 21, '{ "value": "Nothing set!" }'),
    (1000, 22, '{ "value": "Nothing set!" }'),
    (1000, 23, '{ "value": "Nothing set!" }'),
    (1000, 24, '{ "value": "" }'),
    (
        1000,
        25,
        '{ "isRefundPolicyAvailable": true, "isPrivacyPolicyAvailable": true, "isTermsAndConditionsAvailable": true }'
    ),
    (
        1000,
        26,
        '{ "name": "Test", "email": "no-reply@dailykit.org", "template": { "data": { "id": "{{new.id}}" }, "template": { "name": "order_delivered", "type": "email", "format": "html" } } }'
    ),
    (
        1000,
        27,
        '{ "name": "Test", "email": "no-reply@dailykit.org", "template": { "data": { "id": "{{new.id}}" }, "template": { "name": "order_cancelled", "type": "email", "format": "html" } } }'
    );

-- APPS LISTING
INSERT INTO
    settings.app (id, title, route, icon)
VALUES
    (
        1,
        'Orders',
        '/order',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/order.png'
    ),
    (
        2,
        'Products',
        '/products',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/product.png'
    ),
    (
        3,
        'Inventory',
        '/inventory',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/inventory.png'
    ),
    (
        4,
        'Manage Subscription',
        '/subscription',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/subscription.png'
    ),
    (
        5,
        'CRM',
        '/crm',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/crm.png'
    ),
    (
        6,
        'Settings',
        '/settings',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/settings.png'
    ),
    (
        7,
        'Safety',
        '/safety',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/safety.png'
    ),
    (
        8,
        'Menu',
        '/menu',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/menu.png'
    ),
    (
        9,
        'Brands',
        '/brands',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/brand.png'
    ),
    (
        10,
        'Insights',
        '/insights',
        'https://s3.us-east-2.amazonaws.com/dailykit.org/app_icons/insights.png'
    ),
    (11, 'Editor', '/editor', null),
    (12, 'Manage Content', '/content', null);

-- APP PERMISSIONS
INSERT INTO
    settings."appPermission" ("appId", route, title, "fallbackMessage")
VALUES
    -- Order App
    (
        1,
        'orders',
        'ROUTE_READ',
        'You do not have sufficient permission to see orders listing'
    ),
    (
        1,
        'planned',
        'ROUTE_READ',
        'You do not have sufficient permission to see planned mode.'
    ),
    (
        1,
        'order',
        'ROUTE_READ',
        'You do not have sufficient permission to see order details.'
    ),
    (
        1,
        'planned/ready-to-eat',
        'ROUTE_READ',
        'You do not have sufficient permission to see planned ready to eat details.'
    ),
    (
        1,
        'planned/inventory',
        'ROUTE_READ',
        'You do not have sufficient permission to see planned inventory details.'
    ),
    (
        1,
        'home',
        'ROUTE_READ',
        'You do not have sufficient permission to see order app.'
    ) -- Recipe App
,
    (
        2,
        'home',
        'ROUTE_READ',
        'You do not have sufficient permission to see products app.'
    ),
    (
        2,
        'recipes',
        'ROUTE_READ',
        'You do not have sufficient permission to see recipes listing.'
    ),
    (
        2,
        'recipe',
        'ROUTE_READ',
        'You do not have sufficient permission to see recipe details.'
    ),
    (
        2,
        'ingredients',
        'ROUTE_READ',
        'You do not have sufficient permission to see ingredients listing.'
    ),
    (
        2,
        'ingredient',
        'ROUTE_READ',
        'You do not have sufficient permission to see ingredient details.'
    ),
    (
        2,
        'simple-recipe-product',
        'ROUTE_READ',
        'You do not have sufficient permission to see simple recipe product details.'
    ),
    (
        2,
        'customizable-product',
        'ROUTE_READ',
        'You do not have sufficient permission to see customizable product details.'
    ),
    (
        2,
        'combo-product',
        'ROUTE_READ',
        'You do not have sufficient permission to see combo product details.'
    ),
    (
        2,
        'products',
        'ROUTE_READ',
        'You do not have sufficient permission to see products listing.'
    ),
    (
        2,
        'inventory-product',
        'ROUTE_READ',
        'You do not have sufficient permission to see inventory product details.'
    ) -- Inventory App
,
    (
        3,
        'suppliers',
        'ROUTE_READ',
        'You do not have sufficient permission to see suppliers listing.'
    ),
    (
        3,
        'supplier',
        'ROUTE_READ',
        'You do not have sufficient permission to see suppliers details.'
    ),
    (
        3,
        'home',
        'ROUTE_READ',
        'You do not have sufficient permission to see inventory app.'
    ),
    (
        3,
        'items',
        'ROUTE_READ',
        'You do not have sufficient permission to see items listing.'
    ),
    (
        3,
        'item',
        'ROUTE_READ',
        'You do not have sufficient permission to see item details.'
    ),
    (
        3,
        'work-orders',
        'ROUTE_READ',
        'You do not have sufficient permission to see work orders.'
    ),
    (
        3,
        'work-orders/sachet',
        'ROUTE_READ',
        'You do not have sufficient permission to see work order sachet.'
    ),
    (
        3,
        'work-orders/bulk',
        'ROUTE_READ',
        'You do not have sufficient permission to see work order bulk.'
    ),
    (
        3,
        'purchase-orders',
        'ROUTE_READ',
        'You do not have sufficient permission to see purchase orders.'
    ),
    (
        3,
        'purchase-orders/item',
        'ROUTE_READ',
        'You do not have sufficient permission to see purchase order item.'
    ),
    (
        3,
        'purchase-orders/packaging',
        'ROUTE_READ',
        'You do not have sufficient permission to see purchase order packaging.'
    ),
    (
        3,
        'packagings',
        'ROUTE_READ',
        'You do not have sufficient permission to see packagings.'
    ),
    (
        3,
        'packaging',
        'ROUTE_READ',
        'You do not have sufficient permission to see packagings details.'
    ),
    (
        3,
        'packaging-hub',
        'ROUTE_READ',
        'You do not have sufficient permission to see packaging hub.'
    ),
    (
        3,
        'packaging-hub/product',
        'ROUTE_READ',
        'You do not have sufficient permission to see packaging hub product.'
    ),
    (
        3,
        'packaging-hub/products',
        'ROUTE_READ',
        'You do not have sufficient permission to see packaging hub products.'
    ) -- Subscription App
,
    (
        4,
        'home',
        'ROUTE_READ',
        'You do not have sufficient permission to see subscription app.'
    ),
    (
        4,
        'menu',
        'ROUTE_READ',
        'You do not have sufficient permission to see menu page.'
    ),
    (
        4,
        'subscriptions',
        'ROUTE_READ',
        'You do not have sufficient permission to see subscription listing.'
    ),
    (
        4,
        'subscription',
        'ROUTE_READ',
        'You do not have sufficient permission to see subscription details.'
    ) -- CRM App
,
    (
        5,
        'home',
        'ROUTE_READ',
        'You do not have sufficient permission to see crm app.'
    ),
    (
        5,
        'customers',
        'ROUTE_READ',
        'You do not have sufficient permission to see customers listing.'
    ),
    (
        5,
        'referral-plans',
        'ROUTE_READ',
        'You do not have sufficient permission to see referral plans.'
    ),
    (
        5,
        'coupons',
        'ROUTE_READ',
        'You do not have sufficient permission to see coupons listing.'
    ),
    (
        5,
        'campaigns',
        'ROUTE_READ',
        'You do not have sufficient permission to see campaign listing.'
    ),
    (
        5,
        'campaign',
        'ROUTE_READ',
        'You do not have sufficient permission to see campaign details.'
    ),
    (
        5,
        'customer',
        'ROUTE_READ',
        'You do not have sufficient permission to see customer details.'
    ),
    (
        5,
        'coupon',
        'ROUTE_READ',
        'You do not have sufficient permission to see coupon details.'
    ) -- Settings App
,
    (
        6,
        'home',
        'ROUTE_READ',
        'You do not have sufficient permission to see settings app.'
    ),
    (
        6,
        'apps',
        'ROUTE_READ',
        'You do not have sufficient permission to see apps listing.'
    ),
    (
        6,
        'users',
        'ROUTE_READ',
        'You do not have sufficient permission to see users listing.'
    ),
    (
        6,
        'user',
        'ROUTE_READ',
        'You do not have sufficient permission to see user details.'
    ),
    (
        6,
        'roles',
        'ROUTE_READ',
        'You do not have sufficient permission to see roles listing.'
    ),
    (
        6,
        'role',
        'ROUTE_READ',
        'You do not have sufficient permission to see role details.'
    ),
    (
        6,
        'devices',
        'ROUTE_READ',
        'You do not have sufficient permission to see devices listing.'
    ),
    (
        6,
        'stations',
        'ROUTE_READ',
        'You do not have sufficient permission to see stations listing.'
    ),
    (
        6,
        'station',
        'ROUTE_READ',
        'You do not have sufficient permission to see station details.'
    ),
    (
        6,
        'master-lists',
        'ROUTE_READ',
        'You do not have sufficient permission to see master listing.'
    ),
    (
        6,
        'master-list',
        'ROUTE_READ',
        'You do not have sufficient permission to see master list details.'
    ) -- Safety App
,
    (
        7,
        'home',
        'ROUTE_READ',
        'You do not have sufficient permission to see safety app.'
    ),
    (
        7,
        'checks',
        'ROUTE_READ',
        'You do not have sufficient permission to see checks listing.'
    ),
    (
        7,
        'check',
        'ROUTE_READ',
        'You do not have sufficient permission to see check details.'
    ) -- Online Store
,
    (
        8,
        'home',
        'ROUTE_READ',
        'You do not have sufficient permission to see store app.'
    ),
    (
        8,
        'collections',
        'ROUTE_READ',
        'You do not have sufficient permission to see collections listing.'
    ),
    (
        8,
        'collection',
        'ROUTE_READ',
        'You do not have sufficient permission to see collection details.'
    ),
    (
        8,
        'settings',
        'ROUTE_READ',
        'You do not have sufficient permission to see store settings.'
    ),
    (
        8,
        'recurrence',
        'ROUTE_READ',
        'You do not have sufficient permission to see recurrence details.'
    ) -- Brand App
,
    (
        9,
        'home',
        'ROUTE_READ',
        'You do not have sufficient permission to see brand app.'
    ),
    (
        9,
        'brands',
        'ROUTE_READ',
        'You do not have sufficient permission to see brands listing'
    ),
    (
        9,
        'brand',
        'ROUTE_READ',
        'You do not have sufficient permission to see brand details.'
    );

--  ORDER APP SETTINGS
INSERT INTO
    settings."appSettings" (id, app, "type", identifier, value)
VALUES
    (
        1,
        'order',
        'scale',
        'weight simulation',
        '{"isActive": true}'
    ),
    (
        2,
        'order',
        'print',
        'print simulation',
        '{"isActive": true}'
    ),
    (
        3,
        'order',
        'kot',
        'group by station',
        '{"isActive": true}'
    ),
    (
        4,
        'order',
        'kot',
        'group by product type',
        '{"isActive": true}'
    ),
    (
        5,
        'order',
        'kot',
        'print automatically',
        '{"isActive": true}'
    ),
    (
        6,
        'order',
        'kot',
        'default kot printer',
        '{"printNodeId": 69670740}'
    );

-- ADMIN ROLE
INSERT INTO
    settings."role" (id, title)
VALUES
    (1, 'admin');

-- APPS ROLES
INSERT INTO
    settings."role_app" (id, "roleId", "appId")
VALUES
    (1, 1, 1),
    (2, 1, 2),
    (3, 1, 3),
    (4, 1, 4),
    (5, 1, 5),
    (6, 1, 6),
    (7, 1, 7),
    (8, 1, 8),
    (9, 1, 9),
    (10, 1, 10),
    (11, 1, 11),
    (12, 1, 12);

-- ROLE PERMISSIONS
INSERT INTO
    settings."role_appPermission" ("role_appId", "appPermissionId", value)
VALUES
    (1, 1000, true),
    (1, 1001, true),
    (1, 1002, true),
    (1, 1003, true),
    (1, 1004, true),
    (1, 1005, true),
    (2, 1006, true),
    (2, 1007, true),
    (2, 1008, true),
    (2, 1009, true),
    (2, 1010, true),
    (2, 1011, true),
    (2, 1012, true),
    (2, 1013, true),
    (2, 1014, true),
    (2, 1015, true),
    (3, 1016, true),
    (3, 1017, true),
    (3, 1018, true),
    (3, 1019, true),
    (3, 1020, true),
    (3, 1021, true),
    (3, 1022, true),
    (3, 1023, true),
    (3, 1024, true),
    (3, 1025, true),
    (3, 1026, true),
    (3, 1027, true),
    (3, 1028, true),
    (3, 1029, true),
    (3, 1030, true),
    (3, 1031, true),
    (4, 1032, true),
    (4, 1033, true),
    (4, 1034, true),
    (4, 1035, true),
    (5, 1036, true),
    (5, 1037, true),
    (5, 1038, true),
    (5, 1039, true),
    (5, 1040, true),
    (5, 1041, true),
    (5, 1042, true),
    (5, 1043, true),
    (6, 1044, true),
    (6, 1045, true),
    (6, 1046, true),
    (6, 1047, true),
    (6, 1048, true),
    (6, 1049, true),
    (6, 1050, true),
    (6, 1051, true),
    (6, 1052, true),
    (6, 1053, true),
    (6, 1054, true),
    (7, 1055, true),
    (7, 1056, true),
    (7, 1057, true),
    (8, 1058, true),
    (8, 1059, true),
    (8, 1060, true),
    (8, 1061, true),
    (8, 1062, true),
    (9, 1063, true),
    (9, 1064, true),
    (9, 1065, true);

-- CRM CAMPAIGNS
INSERT INTO
    crm."campaignType" (id, value)
VALUES
    (1, 'Sign Up'),
    (2, 'Referral'),
    (3, 'Post Order');

-- CRM REWARDS
INSERT INTO
    crm."rewardType" (id, value, "useForCoupon", handler)
VALUES
    (1, 'Loyalty Point Credit', true, 'jaguar'),
    (2, 'Wallet Amount Credit', true, 'jaguar'),
    (3, 'Discount', true, 'cart');

-- CRM CAMPAIGN REWARDS
INSERT INTO
    crm."rewardType_campaignType" ("rewardTypeId", "campaignTypeId")
VALUES
    (1, 1),
    (2, 1),
    (1, 2),
    (2, 2),
    (1, 3),
    (2, 3);