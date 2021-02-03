alter table "products"."inventoryProduct"
           add constraint "inventoryProduct_importHistoryId_fkey"
           foreign key ("importHistoryId")
           references "imports"."importHistory"
           ("id") on update restrict on delete cascade;
