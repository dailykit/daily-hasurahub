INSERT INTO "order"."orderStatusEnum" 
            (value, 
             description, index) 
VALUES      ('PENDING', 
             'pending',1), 
            ('UNDER_PROCESSING', 
             'order is processing',2), 
            ('READY_TO_ASSEMBLE', 
             'order is ready to assemble',3), 
            ('READY_TO_DISPATCH', 
             'order is ready for delivery',4), 
            ('OUT_FOR_DELIVERY', 
             'order is in transit',5), 
            ('DELIVERED', 
             'order is delivered',6), 
            ('REJECTED_OR_CANCELLED', 
             'order is rejected or cancelled',7); 


INSERT INTO "order"."orderSachetStatusEnum" 
            (value, 
             description) 
VALUES      ('PENDING', 
             'pending'), 
            ('PACKED', 
             'Item is packed'); 

INSERT INTO "order"."assemblyEnum" 
            (value, 
             description) 
VALUES      ('PENDING', 
             'pending'), 
            ('COMPLETED', 
             'Item has been assembled'); 

INSERT INTO notifications."type" 
            (id, 
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
             "webhookEnv") 
VALUES      ('0f8d450e-bfd3-4aeb-bc75-871a49c700ad', 
             'Recipe_Created', 
             NULL, 
             'Recipe', 
             'simpleRecipe', 
             'simpleRecipe', 
             'INSERT', 
             '{}', 
             false, 
'{"title": "A new Recipe has been created", "description": "Recipe Name: {{new.name}}"}' 
             , 
true, 
true, 
true, 
NULL, 
'WEBHOOK_DEFAULT_NOTIFICATION_HANDLER'), 
            ('d8252226-e96e-42f6-9320-709d282181d7', 
             'Order_Created', 
             NULL, 
             'Order', 
             'order', 
             'order', 
             'INSERT', 
             '{}', 
             true, 
'{"title": "A new order placed by {{new.deliveryInfo.dropoff.dropoffInfo.customerFirstName}} {{new.deliveryInfo.dropoff.dropoffInfo.customerLastName}}.", "action": {"url": "/apps/order/orders/{{new.id}}"}, "description": "Order Id: {{new.id}} of amount {{new.currency}}{{new.itemTotal}}."}' 
             , 
true, 
true, 
false, 
'https://dailykit-100-gdbro.s3.us-east-2.amazonaws.com/sounds/beep.mp3', 
'WEBHOOK_DEFAULT_NOTIFICATION_HANDLER'), 
            ('9ed3841a-bf97-496a-bb23-fcb33c63c40b', 
             'Recipe_Updated', 
             NULL, 
             'Recipe', 
             'simpleRecipe', 
             'simpleRecipe', 
             'UPDATE', 
             '{"columns": ["name", "cuisine"]}', 
             false, 
'{"title": "A new Recipe has been updated", "action": {"url": "/recipe/recipes/{{new.id}}"}, "description": "Recipe Old Name: {{old.name}} {{old.cuisine}} , Recipe New Name: {{new.name}} {{new.cuisine}} "}'
             , 
true, 
true, 
false, 
NULL, 
'WEBHOOK_DEFAULT_NOTIFICATION_HANDLER'); 


INSERT INTO fulfilment."fulfillmentType" 
            (value, 
             "isActive") 
VALUES      ('ONDEMAND_DELIVERY', 
             true), 
            ('ONDEMAND_PICKUP', 
             true), 
            ('PREORDER_PICKUP', 
             true), 
            ('PREORDER_DELIVERY', 
             true); 

INSERT INTO "deviceHub"."printerType" 
            ("type") 
VALUES      ('LABEL_PRINTER'), 
            ('RECEIPT_PRINTER'), 
            ('OTHER_PRINTER'); 


INSERT INTO ingredient."modeOfFulfillmentEnum" 
            (value, 
             description) 
VALUES      ('realTime', 
             'realm time'), 
            ('plannedLot', 
             'planned lot'); 

INSERT INTO "order"."orderPaymentStatusEnum" 
            (value, 
             description) 
VALUES      ('PENDING', 
             'pending');
			 
INSERT INTO fulfilment."deliveryService"
			("isThirdParty",
			"isActive",
			"companyName")
VALUES		(false,
			true,
			'Self');
