alter table "brands"."brand_storeSetting" drop constraint "brand_storeSetting_storeSettingId_fkey",
          add constraint "brand_storeSetting_storeSettingId_fkey"
          foreign key ("storeSettingId")
          references "brands"."storeSetting"
          ("id")
          on update restrict
          on delete restrict;
