CREATE TABLE "order"."order" (
    id oid DEFAULT public.defaultid('order'::text, 'order'::text, 'id'::text) NOT NULL,
    "deliveryInfo" jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tax double precision,
    discount numeric DEFAULT 0 NOT NULL,
    "itemTotal" numeric,
    "deliveryPrice" numeric,
    currency text DEFAULT 'usd'::text,
    updated_at timestamp with time zone DEFAULT now(),
    tip numeric,
    "amountPaid" numeric,
    "fulfillmentType" text,
    "deliveryPartnershipId" integer,
    "cartId" integer,
    "isRejected" boolean,
    "isAccepted" boolean,
    "thirdPartyOrderId" integer,
    "readyByTimestamp" timestamp without time zone,
    "fulfillmentTimestamp" timestamp without time zone,
    "keycloakId" text,
    "brandId" integer
);
CREATE TABLE products."customizableProductComponent" (
    id integer DEFAULT public.defaultid('products'::text, 'customizableProductComponent'::text, 'id'::text) NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "isArchived" boolean DEFAULT false NOT NULL,
    options jsonb DEFAULT '[]'::jsonb NOT NULL,
    "position" numeric,
    "productId" integer,
    "linkedProductId" integer
);

CREATE TABLE products."comboProductComponent" (
    id integer DEFAULT public.defaultid('products'::text, 'comboProductComponent'::text, 'id'::text) NOT NULL,
    label text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    "isArchived" boolean DEFAULT false NOT NULL,
    options jsonb DEFAULT '[]'::jsonb NOT NULL,
    "position" numeric,
    "productId" integer,
    "linkedProductId" integer
);

CREATE TABLE products.product (
    id integer DEFAULT public.defaultid('products'::text, 'product'::text, 'id'::text) NOT NULL,
    name text,
    "additionalText" text,
    description text,
    assets jsonb DEFAULT jsonb_build_object('images', '[]'::jsonb, 'videos', '[]'::jsonb) NOT NULL,
    "isPublished" boolean DEFAULT false NOT NULL,
    "isPopupAllowed" boolean DEFAULT true NOT NULL,
    "defaultProductOptionId" integer,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    tags jsonb,
    "isArchived" boolean DEFAULT false NOT NULL,
    type text DEFAULT 'simple'::text NOT NULL,
    price numeric DEFAULT 0 NOT NULL,
    discount numeric DEFAULT 0 NOT NULL,
    "importHistoryId" integer
);

CREATE TABLE "simpleRecipe"."simpleRecipeComponent_productOptionType" (
    "simpleRecipeComponentId" integer NOT NULL,
    "productOptionType" text NOT NULL,
    "orderMode" text NOT NULL
);

CREATE TABLE "simpleRecipe"."simpleRecipeYield_ingredientSachet" (
    "recipeYieldId" integer NOT NULL,
    "ingredientSachetId" integer,
    "isVisible" boolean DEFAULT true NOT NULL,
    "slipName" text,
    "isSachetValid" boolean,
    "isArchived" boolean DEFAULT false NOT NULL,
    "simpleRecipeIngredientProcessingId" integer NOT NULL,
    "subRecipeYieldId" integer,
    "simpleRecipeId" integer
);


CREATE TABLE "simpleRecipe"."simpleRecipe_productOptionType" (
    "simpleRecipeId" integer NOT NULL,
    "productOptionTypeTitle" text NOT NULL,
    "orderMode" text NOT NULL
);

CREATE TABLE website."navigationMenu" (
    id integer DEFAULT public.defaultid('website'::text, 'navigationMenu'::text, 'id'::text) NOT NULL,
    title text NOT NULL,
    "isPublished" boolean DEFAULT false NOT NULL
);
