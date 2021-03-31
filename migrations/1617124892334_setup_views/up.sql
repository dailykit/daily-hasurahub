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