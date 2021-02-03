alter table "onDemand"."collection_productCategory_product"
           add constraint "collection_productCategory_product_importHistoryId_fkey"
           foreign key ("importHistoryId")
           references "imports"."importHistory"
           ("id") on update restrict on delete cascade;
