-- insert into to_magento_records

insert into to_magento_records (record_id, identifier, `type`, `status`)
values (4, 0, 1, 0);

-- insert into to_magento_datas

insert into to_magento_datas (record_id, field_name, field_value)
values (4, 'action', 1);

-- default store
insert into to_magento_datas (record_id, field_name, field_value)
values (4, 'cat_name_admin', 'Jeans');

insert into to_magento_datas (record_id, field_name, field_value)
values (4, 'cat_is_active_admin', 1);

insert into to_magento_datas (record_id, field_name, field_value)
values (4, 'cat_url_key_admin', 'jeans');

insert into to_magento_datas (record_id, field_name, field_value)
values (4, 'cat_description_admin', 'Jeans Category Description');

insert into to_magento_datas (record_id, field_name, field_value)
values (4, 'cat_include_in_menu_admin', 1);

-- select * from to_magento_records;

-- update record to status 1 = ready for processing
update to_magento_records set status = 1 where id = 3;