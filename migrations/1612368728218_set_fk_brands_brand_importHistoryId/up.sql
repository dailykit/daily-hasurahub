alter table "brands"."brand"
           add constraint "brand_importHistoryId_fkey"
           foreign key ("importHistoryId")
           references "imports"."importHistory"
           ("id") on update restrict on delete cascade;
