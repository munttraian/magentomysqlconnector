-- insert into to_magento_records

insert into to_magento_records (record_id, identifier, `type`, `status`)
values (5, 0, 1, 0);

-- insert into to_magento_datas

insert into to_magento_datas (record_id, field_name, field_value)
values (5, 'action', 1);

-- default store
insert into to_magento_datas (record_id, field_name, field_value)
values (5, 'cat_name_admin', 'Jeans Test');

insert into to_magento_datas (record_id, field_name, field_value)
values (5, 'cat_is_active_admin', 1);

insert into to_magento_datas (record_id, field_name, field_value)
values (5, 'cat_url_key_admin', 'jeans');

insert into to_magento_datas (record_id, field_name, field_value)
values (5, 'cat_description_admin', 'Jeans Category Description');

insert into to_magento_datas (record_id, field_name, field_value)
values (5, 'cat_include_in_menu_admin', 1);

insert into to_magento_datas (record_id, field_name, field_value)
values (5, 'cat_display_mode_admin', 'PRODUCTS_AND_PAGE');

-- get the id from to_magento_records where record_id = 5
select * from to_magento_records where record_id = 5;
-- id = 4

-- update record to status 1 = ready for processing
update to_magento_records set status = 1 where id = 4;