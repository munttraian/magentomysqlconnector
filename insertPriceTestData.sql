SET @maxRecordId = (SELECT max(record_id) from to_magento_records);

insert into to_magento_records (`record_id`, `identifier`, `type`, `status`)
values (@maxRecordId + 1, 'Vj0212', 4, 0);

insert into to_magento_datas (`record_id`, `field_name`, `field_value`)
values (@maxRecordId + 1, 'Vejl_DKK', 200),
(@maxRecordId + 1, 'Vejl_EUR', 120), 
(@maxRecordId + 1, 'Vejl_NOK', 100), 
(@maxRecordId + 1, 'Vejl_SEK', 140), 
(@maxRecordId + 1, 'Vejl_GBP', 100),
(@maxRecordId + 1, 'Kost', 100);