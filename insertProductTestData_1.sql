-- insert into to_magento_records

insert into to_magento_records (`record_id`, `identifier`, `type`, `status`)
values (6, 'XXX001', 2, 0);

-- insert into to_magento_datas

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'action', 1);

-- default store
insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_name_admin', 'Denimio Jeans XXX-001');

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_description_admin', 'Quality Jeans with a beautifull design ...');

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_short_description_admin', 'Quality Jeans with a beautifull design');

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_weight_admin', '0.7');

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_status_admin', 1);

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_visibility_admin', 4);

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_category_ids', '19');

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_media_gallery', 'XXX001_1.jpg,XXX001_2.jpg,XXX001_3.jpg');

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_price_admin', 200);

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_type_id', 'simple');

insert into to_magento_datas (record_id, field_name, field_value)
values (6, 'prod_website_ids', '1,2,3,4');

-- get the id from to_magento_records where record_id = 5
select * from to_magento_records where record_id = 6;
-- id = 4

select * from to_magento_datas where record_id = 6;

-- update record to status 1 = ready for processing
update to_magento_records set status = 1 where id = 5;