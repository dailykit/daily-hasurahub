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

CREATE VIEW crm.view_brand_customer AS
SELECT
    brand_customer.id,
    brand_customer."keycloakId",
    brand_customer."brandId",
    brand_customer.created_at,
    brand_customer.updated_at,
    brand_customer."isSubscriber",
    brand_customer."subscriptionId",
    brand_customer."subscriptionAddressId",
    brand_customer."subscriptionPaymentMethodId",
    brand_customer."isAutoSelectOptOut",
    brand_customer."isSubscriberTimeStamp",
    brand_customer."subscriptionServingId",
    brand_customer."subscriptionItemCountId",
    brand_customer."subscriptionTitleId",
    (
        SELECT
            subscription."customerSubscriptionReport"(
                brand_customer.id,
                'All' :: text
            ) AS "customerSubscriptionReport"
    ) AS "allSubscriptionOccurences",
    (
        SELECT
            subscription."customerSubscriptionReport"(
                brand_customer.id,
                'Skipped' :: text
            ) AS "customerSubscriptionReport"
    ) AS "skippedSubscriptionOccurences"
FROM
    crm.brand_customer;

CREATE VIEW ingredient."ingredientProcessingView" AS
SELECT
    "ingredientProcessing".id,
    "ingredientProcessing"."processingName",
    "ingredientProcessing"."ingredientId",
    "ingredientProcessing"."nutritionalInfo",
    "ingredientProcessing".cost,
    "ingredientProcessing".created_at,
    "ingredientProcessing".updated_at,
    "ingredientProcessing"."isArchived",
    concat(
        (
            SELECT
                ingredient.name
            FROM
                ingredient.ingredient
            WHERE
                (
                    ingredient.id = "ingredientProcessing"."ingredientId"
                )
        ),
        ' - ',
        "ingredientProcessing"."processingName"
    ) AS "displayName"
FROM
    ingredient."ingredientProcessing";

CREATE VIEW ingredient."ingredientSachetView" AS
SELECT
    "ingredientSachet".id,
    "ingredientSachet".quantity,
    "ingredientSachet"."ingredientProcessingId",
    "ingredientSachet"."ingredientId",
    "ingredientSachet"."createdAt",
    "ingredientSachet"."updatedAt",
    "ingredientSachet".tracking,
    "ingredientSachet".unit,
    "ingredientSachet".visibility,
    "ingredientSachet"."liveMOF",
    "ingredientSachet"."isArchived",
    concat(
        (
            SELECT
                "ingredientProcessingView"."displayName"
            FROM
                ingredient."ingredientProcessingView"
            WHERE
                (
                    "ingredientProcessingView".id = "ingredientSachet"."ingredientProcessingId"
                )
        ),
        ' - ',
        "ingredientSachet".quantity,
        "ingredientSachet".unit
    ) AS "displayName"
FROM
    ingredient."ingredientSachet";

CREATE VIEW inventory."bulkItemView" AS
SELECT
    "bulkItem"."supplierItemId",
    "bulkItem"."processingName",
    (
        SELECT
            "supplierItem".name
        FROM
            inventory."supplierItem"
        WHERE
            ("supplierItem".id = "bulkItem"."supplierItemId")
    ) AS "supplierItemName",
    (
        SELECT
            "supplierItem"."supplierId"
        FROM
            inventory."supplierItem"
        WHERE
            ("supplierItem".id = "bulkItem"."supplierItemId")
    ) AS "supplierId",
    "bulkItem".id,
    "bulkItem"."bulkDensity"
FROM
    inventory."bulkItem";

CREATE VIEW inventory."sachetItemView" AS
SELECT
    "sachetItem".id,
    "sachetItem"."unitSize",
    "sachetItem"."bulkItemId",
    (
        SELECT
            "bulkItemView"."supplierItemName"
        FROM
            inventory."bulkItemView"
        WHERE
            ("bulkItemView".id = "sachetItem"."bulkItemId")
    ) AS "supplierItemName",
    (
        SELECT
            "bulkItemView"."processingName"
        FROM
            inventory."bulkItemView"
        WHERE
            ("bulkItemView".id = "sachetItem"."bulkItemId")
    ) AS "processingName",
    (
        SELECT
            "bulkItemView"."supplierId"
        FROM
            inventory."bulkItemView"
        WHERE
            ("bulkItemView".id = "sachetItem"."bulkItemId")
    ) AS "supplierId",
    "sachetItem".unit,
    (
        SELECT
            "bulkItem"."bulkDensity"
        FROM
            inventory."bulkItem"
        WHERE
            ("bulkItem".id = "sachetItem"."bulkItemId")
    ) AS "bulkDensity"
FROM
    inventory."sachetItem";

CREATE VIEW inventory."supplierItemView" AS
SELECT
    "supplierItem"."supplierId",
    "supplierItem".name AS "supplierItemName",
    "supplierItem"."unitSize",
    "supplierItem".unit,
    (
        SELECT
            "bulkItemView"."processingName"
        FROM
            inventory."bulkItemView"
        WHERE
            (
                "bulkItemView".id = "supplierItem"."bulkItemAsShippedId"
            )
    ) AS "processingName",
    "supplierItem".id,
    (
        SELECT
            "bulkItem"."bulkDensity"
        FROM
            inventory."bulkItem"
        WHERE
            (
                "bulkItem".id = "supplierItem"."bulkItemAsShippedId"
            )
    ) AS "bulkDensity"
FROM
    inventory."supplierItem";

CREATE VIEW "onDemand"."collectionDetails" AS
SELECT
    collection.id,
    collection.name,
    collection."startTime",
    collection."endTime",
    collection.rrule,
    "onDemand"."numberOfCategories"(collection.id) AS "categoriesCount",
    "onDemand"."numberOfProducts"(collection.id) AS "productsCount",
    collection.created_at,
    collection.updated_at
FROM
    "onDemand".collection;

CREATE VIEW "onDemand"."modifierCategoryOptionView" AS
SELECT
    "modifierCategoryOption".id,
    "modifierCategoryOption".name,
    "modifierCategoryOption"."originalName",
    "modifierCategoryOption".price,
    "modifierCategoryOption".discount,
    "modifierCategoryOption".quantity,
    "modifierCategoryOption".image,
    "modifierCategoryOption"."isActive",
    "modifierCategoryOption"."isVisible",
    "modifierCategoryOption"."operationConfigId",
    "modifierCategoryOption"."modifierCategoryId",
    "modifierCategoryOption"."sachetItemId",
    "modifierCategoryOption"."ingredientSachetId",
    "modifierCategoryOption"."simpleRecipeYieldId",
    "modifierCategoryOption".created_at,
    "modifierCategoryOption".updated_at,
    concat(
        (
            SELECT
                "modifierCategory".name
            FROM
                "onDemand"."modifierCategory"
            WHERE
                (
                    "modifierCategory".id = "modifierCategoryOption"."modifierCategoryId"
                )
        ),
        ' - ',
        "modifierCategoryOption".name
    ) AS "displayName"
FROM
    "onDemand"."modifierCategoryOption";

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



-- datahub_schema."columns" source

CREATE OR REPLACE VIEW datahub_schema."columns"
AS SELECT columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"."', columns.column_name, '"') AS concat) AS column_reference,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', columns.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.columns
  WHERE columns.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.columns_privileges source

CREATE OR REPLACE VIEW datahub_schema.columns_privileges
AS SELECT columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"."', columns.column_name, '"') AS concat) AS column_reference,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', columns.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.columns
  WHERE columns.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.constraint_column_usage source

CREATE OR REPLACE VIEW datahub_schema.constraint_column_usage
AS SELECT columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"."', columns.column_name, '"') AS concat) AS column_reference,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', columns.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.columns
  WHERE columns.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.constraint_table_usage source

CREATE OR REPLACE VIEW datahub_schema.constraint_table_usage
AS SELECT columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', columns.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.columns
  WHERE columns.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.event_invocation_logs source

CREATE OR REPLACE VIEW datahub_schema.event_invocation_logs
AS SELECT event_invocation_logs.id,
    event_invocation_logs.event_id,
    event_invocation_logs.status,
    event_invocation_logs.request,
    event_invocation_logs.response,
    event_invocation_logs.created_at
   FROM hdb_catalog.event_invocation_logs;


-- datahub_schema.event_log source

CREATE OR REPLACE VIEW datahub_schema.event_log
AS SELECT event_log.id,
    event_log.schema_name,
    event_log.table_name,
    event_log.trigger_name,
    event_log.payload,
    event_log.delivered,
    event_log.error,
    event_log.tries,
    event_log.created_at,
    event_log.locked,
    event_log.next_retry_at,
    event_log.archived
   FROM hdb_catalog.event_log;


-- datahub_schema.event_triggers source

CREATE OR REPLACE VIEW datahub_schema.event_triggers
AS SELECT event_triggers.name,
    event_triggers.type,
    event_triggers.schema_name,
    event_triggers.table_name,
    event_triggers.configuration,
    event_triggers.comment
   FROM hdb_catalog.event_triggers;


-- datahub_schema.hdb_action source

CREATE OR REPLACE VIEW datahub_schema.hdb_action
AS SELECT hdb_action.action_name,
    hdb_action.action_defn,
    hdb_action.comment,
    hdb_action.is_system_defined
   FROM hdb_catalog.hdb_action;


-- datahub_schema.hdb_action_log source

CREATE OR REPLACE VIEW datahub_schema.hdb_action_log
AS SELECT hdb_action_log.id,
    hdb_action_log.action_name,
    hdb_action_log.input_payload,
    hdb_action_log.request_headers,
    hdb_action_log.session_variables,
    hdb_action_log.response_payload,
    hdb_action_log.errors,
    hdb_action_log.created_at,
    hdb_action_log.response_received_at,
    hdb_action_log.status
   FROM hdb_catalog.hdb_action_log;


-- datahub_schema.hdb_action_permission source

CREATE OR REPLACE VIEW datahub_schema.hdb_action_permission
AS SELECT hdb_action_permission.action_name,
    hdb_action_permission.role_name,
    hdb_action_permission.definition,
    hdb_action_permission.comment
   FROM hdb_catalog.hdb_action_permission;


-- datahub_schema.hdb_computed_field source

CREATE OR REPLACE VIEW datahub_schema.hdb_computed_field
AS SELECT hdb_computed_field.table_schema,
    hdb_computed_field.table_name,
    hdb_computed_field.computed_field_name,
    hdb_computed_field.definition,
    hdb_computed_field.comment
   FROM hdb_catalog.hdb_computed_field;


-- datahub_schema.hdb_cron_event_invocation_logs source

CREATE OR REPLACE VIEW datahub_schema.hdb_cron_event_invocation_logs
AS SELECT hdb_cron_event_invocation_logs.id,
    hdb_cron_event_invocation_logs.event_id,
    hdb_cron_event_invocation_logs.status,
    hdb_cron_event_invocation_logs.request,
    hdb_cron_event_invocation_logs.response,
    hdb_cron_event_invocation_logs.created_at
   FROM hdb_catalog.hdb_cron_event_invocation_logs;


-- datahub_schema.hdb_cron_events source

CREATE OR REPLACE VIEW datahub_schema.hdb_cron_events
AS SELECT hdb_cron_events.id,
    hdb_cron_events.trigger_name,
    hdb_cron_events.scheduled_time,
    hdb_cron_events.status,
    hdb_cron_events.tries,
    hdb_cron_events.created_at,
    hdb_cron_events.next_retry_at
   FROM hdb_catalog.hdb_cron_events;


-- datahub_schema.hdb_cron_triggers source

CREATE OR REPLACE VIEW datahub_schema.hdb_cron_triggers
AS SELECT hdb_cron_triggers.name,
    hdb_cron_triggers.webhook_conf,
    hdb_cron_triggers.cron_schedule,
    hdb_cron_triggers.payload,
    hdb_cron_triggers.retry_conf,
    hdb_cron_triggers.header_conf,
    hdb_cron_triggers.include_in_metadata,
    hdb_cron_triggers.comment
   FROM hdb_catalog.hdb_cron_triggers;


-- datahub_schema.hdb_custom_types source

CREATE OR REPLACE VIEW datahub_schema.hdb_custom_types
AS SELECT hdb_custom_types.custom_types
   FROM hdb_catalog.hdb_custom_types;


-- datahub_schema.hdb_function source

CREATE OR REPLACE VIEW datahub_schema.hdb_function
AS SELECT hdb_function.function_schema,
    hdb_function.function_name,
    hdb_function.configuration,
    hdb_function.is_system_defined
   FROM hdb_catalog.hdb_function;


-- datahub_schema.hdb_permission source

CREATE OR REPLACE VIEW datahub_schema.hdb_permission
AS SELECT hdb_permission.table_schema,
    hdb_permission.table_name,
    hdb_permission.role_name,
    hdb_permission.perm_type,
    hdb_permission.perm_def,
    hdb_permission.comment,
    hdb_permission.is_system_defined
   FROM hdb_catalog.hdb_permission;


-- datahub_schema.hdb_relationship source

CREATE OR REPLACE VIEW datahub_schema.hdb_relationship
AS SELECT hdb_relationship.table_schema,
    hdb_relationship.table_name,
    hdb_relationship.rel_name,
    hdb_relationship.rel_type,
    hdb_relationship.rel_def,
    hdb_relationship.comment,
    hdb_relationship.is_system_defined
   FROM hdb_catalog.hdb_relationship;


-- datahub_schema.hdb_remote_relationship source

CREATE OR REPLACE VIEW datahub_schema.hdb_remote_relationship
AS SELECT hdb_remote_relationship.remote_relationship_name,
    hdb_remote_relationship.table_schema,
    hdb_remote_relationship.table_name,
    hdb_remote_relationship.definition
   FROM hdb_catalog.hdb_remote_relationship;


-- datahub_schema.hdb_scheduled_event_invocation_logs source

CREATE OR REPLACE VIEW datahub_schema.hdb_scheduled_event_invocation_logs
AS SELECT hdb_scheduled_event_invocation_logs.id,
    hdb_scheduled_event_invocation_logs.event_id,
    hdb_scheduled_event_invocation_logs.status,
    hdb_scheduled_event_invocation_logs.request,
    hdb_scheduled_event_invocation_logs.response,
    hdb_scheduled_event_invocation_logs.created_at
   FROM hdb_catalog.hdb_scheduled_event_invocation_logs;


-- datahub_schema.hdb_scheduled_events source

CREATE OR REPLACE VIEW datahub_schema.hdb_scheduled_events
AS SELECT hdb_scheduled_events.id,
    hdb_scheduled_events.webhook_conf,
    hdb_scheduled_events.scheduled_time,
    hdb_scheduled_events.retry_conf,
    hdb_scheduled_events.payload,
    hdb_scheduled_events.header_conf,
    hdb_scheduled_events.status,
    hdb_scheduled_events.tries,
    hdb_scheduled_events.created_at,
    hdb_scheduled_events.next_retry_at,
    hdb_scheduled_events.comment
   FROM hdb_catalog.hdb_scheduled_events;


-- datahub_schema.hdb_table source

CREATE OR REPLACE VIEW datahub_schema.hdb_table
AS SELECT hdb_table.table_schema,
    hdb_table.table_name,
    hdb_table.configuration,
    hdb_table.is_system_defined,
    hdb_table.is_enum,
    ( SELECT concat('"', hdb_table.table_schema, '"."', hdb_table.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', hdb_table.table_schema, '"') AS concat) AS schema_reference
   FROM hdb_catalog.hdb_table;


-- datahub_schema.key_column_usage source

CREATE OR REPLACE VIEW datahub_schema.key_column_usage
AS SELECT columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"."', columns.column_name, '"') AS concat) AS column_reference,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', columns.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.columns
  WHERE columns.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.referential_constraints source

CREATE OR REPLACE VIEW datahub_schema.referential_constraints
AS SELECT referential_constraints.constraint_catalog,
    referential_constraints.constraint_schema,
    referential_constraints.constraint_name,
    referential_constraints.unique_constraint_catalog,
    referential_constraints.unique_constraint_schema,
    referential_constraints.unique_constraint_name,
    referential_constraints.match_option,
    referential_constraints.update_rule,
    referential_constraints.delete_rule,
    ( SELECT concat('"', referential_constraints.constraint_schema, '"."', referential_constraints.constraint_name, '"') AS concat) AS constraint_reference,
    ( SELECT concat('"', referential_constraints.constraint_schema, '"') AS concat) AS constraint_schema_reference
   FROM information_schema.referential_constraints
  WHERE referential_constraints.unique_constraint_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.remote_schemas source

CREATE OR REPLACE VIEW datahub_schema.remote_schemas
AS SELECT remote_schemas.id,
    remote_schemas.name,
    remote_schemas.definition,
    remote_schemas.comment
   FROM hdb_catalog.remote_schemas;


-- datahub_schema.role_column_grant source

CREATE OR REPLACE VIEW datahub_schema.role_column_grant
AS SELECT columns.table_catalog,
    columns.table_schema,
    columns.table_name,
    columns.column_name,
    columns.ordinal_position,
    columns.column_default,
    columns.is_nullable,
    columns.data_type,
    columns.character_maximum_length,
    columns.character_octet_length,
    columns.numeric_precision,
    columns.numeric_precision_radix,
    columns.numeric_scale,
    columns.datetime_precision,
    columns.interval_type,
    columns.interval_precision,
    columns.character_set_catalog,
    columns.character_set_schema,
    columns.character_set_name,
    columns.collation_catalog,
    columns.collation_schema,
    columns.collation_name,
    columns.domain_catalog,
    columns.domain_schema,
    columns.domain_name,
    columns.udt_catalog,
    columns.udt_schema,
    columns.udt_name,
    columns.scope_catalog,
    columns.scope_schema,
    columns.scope_name,
    columns.maximum_cardinality,
    columns.dtd_identifier,
    columns.is_self_referencing,
    columns.is_identity,
    columns.identity_generation,
    columns.identity_start,
    columns.identity_increment,
    columns.identity_maximum,
    columns.identity_minimum,
    columns.identity_cycle,
    columns.is_generated,
    columns.generation_expression,
    columns.is_updatable,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"."', columns.column_name, '"') AS concat) AS column_reference,
    ( SELECT concat('"', columns.table_schema, '"."', columns.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', columns.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.columns
  WHERE columns.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema."routines" source

CREATE OR REPLACE VIEW datahub_schema."routines"
AS SELECT routines.specific_catalog,
    routines.specific_schema,
    routines.specific_name,
    routines.routine_catalog,
    routines.routine_schema,
    routines.routine_name,
    routines.routine_type,
    routines.module_catalog,
    routines.module_schema,
    routines.module_name,
    routines.udt_catalog,
    routines.udt_schema,
    routines.udt_name,
    routines.data_type,
    routines.character_maximum_length,
    routines.character_octet_length,
    routines.character_set_catalog,
    routines.character_set_schema,
    routines.character_set_name,
    routines.collation_catalog,
    routines.collation_schema,
    routines.collation_name,
    routines.numeric_precision,
    routines.numeric_precision_radix,
    routines.numeric_scale,
    routines.datetime_precision,
    routines.interval_type,
    routines.interval_precision,
    routines.type_udt_catalog,
    routines.type_udt_schema,
    routines.type_udt_name,
    routines.scope_catalog,
    routines.scope_schema,
    routines.scope_name,
    routines.maximum_cardinality,
    routines.dtd_identifier,
    routines.routine_body,
    routines.routine_definition,
    routines.external_name,
    routines.external_language,
    routines.parameter_style,
    routines.is_deterministic,
    routines.sql_data_access,
    routines.is_null_call,
    routines.sql_path,
    routines.schema_level_routine,
    routines.max_dynamic_result_sets,
    routines.is_user_defined_cast,
    routines.is_implicitly_invocable,
    routines.security_type,
    routines.to_sql_specific_catalog,
    routines.to_sql_specific_schema,
    routines.to_sql_specific_name,
    routines.as_locator,
    routines.created,
    routines.last_altered,
    routines.new_savepoint_level,
    routines.is_udt_dependent,
    routines.result_cast_from_data_type,
    routines.result_cast_as_locator,
    routines.result_cast_char_max_length,
    routines.result_cast_char_octet_length,
    routines.result_cast_char_set_catalog,
    routines.result_cast_char_set_schema,
    routines.result_cast_char_set_name,
    routines.result_cast_collation_catalog,
    routines.result_cast_collation_schema,
    routines.result_cast_collation_name,
    routines.result_cast_numeric_precision,
    routines.result_cast_numeric_precision_radix,
    routines.result_cast_numeric_scale,
    routines.result_cast_datetime_precision,
    routines.result_cast_interval_type,
    routines.result_cast_interval_precision,
    routines.result_cast_type_udt_catalog,
    routines.result_cast_type_udt_schema,
    routines.result_cast_type_udt_name,
    routines.result_cast_scope_catalog,
    routines.result_cast_scope_schema,
    routines.result_cast_scope_name,
    routines.result_cast_maximum_cardinality,
    routines.result_cast_dtd_identifier,
    ( SELECT concat('"', routines.routine_schema, '"."', routines.routine_name, '"') AS concat) AS routine_reference,
    ( SELECT concat('"', routines.routine_schema, '"') AS concat) AS routine_schema_reference
   FROM information_schema.routines
  WHERE routines.specific_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.schemata source

CREATE OR REPLACE VIEW datahub_schema.schemata
AS SELECT schemata.catalog_name,
    schemata.schema_name,
    schemata.schema_owner,
    schemata.default_character_set_catalog,
    schemata.default_character_set_schema,
    schemata.default_character_set_name,
    schemata.sql_path,
    ( SELECT concat('"', schemata.schema_name, '"') AS concat) AS schema_reference
   FROM information_schema.schemata;


-- datahub_schema."sequences" source

CREATE OR REPLACE VIEW datahub_schema."sequences"
AS SELECT sequences.sequence_catalog,
    sequences.sequence_schema,
    sequences.sequence_name,
    sequences.data_type,
    sequences.numeric_precision,
    sequences.numeric_precision_radix,
    sequences.numeric_scale,
    sequences.start_value,
    sequences.minimum_value,
    sequences.maximum_value,
    sequences.increment,
    sequences.cycle_option,
    sequences.sequence_schema AS schema_reference
   FROM information_schema.sequences
  WHERE sequences.sequence_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.table_constraints source

CREATE OR REPLACE VIEW datahub_schema.table_constraints
AS SELECT table_constraints.constraint_catalog,
    table_constraints.constraint_schema,
    table_constraints.constraint_name,
    table_constraints.table_catalog,
    table_constraints.table_schema,
    table_constraints.table_name,
    table_constraints.constraint_type,
    table_constraints.is_deferrable,
    table_constraints.initially_deferred,
    table_constraints.enforced,
    ( SELECT concat('"', table_constraints.table_schema, '"."', table_constraints.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', table_constraints.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.table_constraints
  WHERE table_constraints.constraint_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.table_privileges source

CREATE OR REPLACE VIEW datahub_schema.table_privileges
AS SELECT table_privileges.grantor,
    table_privileges.grantee,
    table_privileges.table_catalog,
    table_privileges.table_schema,
    table_privileges.table_name,
    table_privileges.privilege_type,
    table_privileges.is_grantable,
    table_privileges.with_hierarchy,
    ( SELECT concat('"', table_privileges.table_schema, '"."', table_privileges.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', table_privileges.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.table_privileges
  WHERE table_privileges.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema."tables" source

CREATE OR REPLACE VIEW datahub_schema."tables"
AS SELECT tables.table_catalog,
    tables.table_schema,
    tables.table_name,
    tables.table_type,
    tables.self_referencing_column_name,
    tables.reference_generation,
    tables.user_defined_type_catalog,
    tables.user_defined_type_schema,
    tables.user_defined_type_name,
    tables.is_insertable_into,
    tables.is_typed,
    tables.commit_action,
    ( SELECT concat('"', tables.table_schema, '"."', tables.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', tables.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.tables
  WHERE tables.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.triggered_update_column source

CREATE OR REPLACE VIEW datahub_schema.triggered_update_column
AS SELECT triggers.trigger_catalog,
    triggers.trigger_schema,
    triggers.trigger_name,
    triggers.event_manipulation,
    triggers.event_object_catalog,
    triggers.event_object_schema,
    triggers.event_object_table,
    triggers.action_order,
    triggers.action_condition,
    triggers.action_statement,
    triggers.action_orientation,
    triggers.action_timing,
    triggers.action_reference_old_table,
    triggers.action_reference_new_table,
    triggers.action_reference_old_row,
    triggers.action_reference_new_row,
    triggers.created,
    ( SELECT concat('"', triggers.trigger_schema, '"."', triggers.trigger_name, '"') AS concat) AS trigger_reference,
    ( SELECT concat('"', triggers.trigger_schema, '"') AS concat) AS schema_reference
   FROM information_schema.triggers
  WHERE triggers.trigger_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.triggers source

CREATE OR REPLACE VIEW datahub_schema.triggers
AS SELECT triggers.trigger_catalog,
    triggers.trigger_schema,
    triggers.trigger_name,
    triggers.event_manipulation,
    triggers.event_object_catalog,
    triggers.event_object_schema,
    triggers.event_object_table,
    triggers.action_order,
    triggers.action_condition,
    triggers.action_statement,
    triggers.action_orientation,
    triggers.action_timing,
    triggers.action_reference_old_table,
    triggers.action_reference_new_table,
    triggers.action_reference_old_row,
    triggers.action_reference_new_row,
    triggers.created,
    ( SELECT concat('"', triggers.trigger_schema, '"."', triggers.trigger_name, '"') AS concat) AS trigger_reference,
    ( SELECT concat('"', triggers.trigger_schema, '"') AS concat) AS schema_reference
   FROM information_schema.triggers
  WHERE triggers.trigger_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.view_column_usage source

CREATE OR REPLACE VIEW datahub_schema.view_column_usage
AS SELECT view_column_usage.view_catalog,
    view_column_usage.view_schema,
    view_column_usage.view_name,
    view_column_usage.table_catalog,
    view_column_usage.table_schema,
    view_column_usage.table_name,
    view_column_usage.column_name,
    ( SELECT concat('"', view_column_usage.view_schema, '"."', view_column_usage.view_name, '"') AS concat) AS view_reference,
    ( SELECT concat('"', view_column_usage.table_schema, '"."', view_column_usage.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', view_column_usage.view_schema, '"') AS concat) AS view_schema_reference,
    ( SELECT concat('"', view_column_usage.table_schema, '"') AS concat) AS table_schema_reference
   FROM information_schema.view_column_usage
  WHERE view_column_usage.view_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.view_routine_usage source

CREATE OR REPLACE VIEW datahub_schema.view_routine_usage
AS SELECT view_routine_usage.table_catalog,
    view_routine_usage.table_schema,
    view_routine_usage.table_name,
    view_routine_usage.specific_catalog,
    view_routine_usage.specific_schema,
    view_routine_usage.specific_name,
    ( SELECT concat('"', view_routine_usage.table_schema, '"."', view_routine_usage.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', view_routine_usage.table_schema, '"') AS concat) AS table_schema_reference
   FROM information_schema.view_routine_usage
  WHERE view_routine_usage.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema.view_table_usage source

CREATE OR REPLACE VIEW datahub_schema.view_table_usage
AS SELECT view_table_usage.view_catalog,
    view_table_usage.view_schema,
    view_table_usage.view_name,
    view_table_usage.table_catalog,
    view_table_usage.table_schema,
    view_table_usage.table_name,
    ( SELECT concat('"', view_table_usage.view_schema, '"."', view_table_usage.view_name, '"') AS concat) AS view_reference,
    ( SELECT concat('"', view_table_usage.table_schema, '"."', view_table_usage.table_name, '"') AS concat) AS table_reference,
    ( SELECT concat('"', view_table_usage.view_schema, '"') AS concat) AS view_schema_reference,
    ( SELECT concat('"', view_table_usage.table_schema, '"') AS concat) AS table_schema_reference
   FROM information_schema.view_table_usage
  WHERE view_table_usage.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);


-- datahub_schema."views" source

CREATE OR REPLACE VIEW datahub_schema."views"
AS SELECT views.table_catalog,
    views.table_schema,
    views.table_name,
    views.view_definition,
    views.check_option,
    views.is_updatable,
    views.is_insertable_into,
    views.is_trigger_updatable,
    views.is_trigger_deletable,
    views.is_trigger_insertable_into,
    ( SELECT concat('"', views.table_schema, '"."', views.table_name, '"') AS concat) AS view_reference,
    ( SELECT concat('"', views.table_schema, '"') AS concat) AS schema_reference
   FROM information_schema.views
  WHERE views.table_schema::name <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name]);