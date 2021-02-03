alter table "brands"."brand_storeSetting" drop constraint "brand_storeSetting_brandId_fkey",
             add constraint "brand_storeSetting_brandId_fkey"
             foreign key ("brandId")
             references "brands"."brand"
             ("id") on update restrict on delete cascade;
