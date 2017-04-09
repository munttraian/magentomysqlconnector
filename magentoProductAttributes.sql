INSERT INTO magento_field_matches (`type`, `cloud_biz_field_name`, `magento_field_name`, `magento_attribute_id`, `magento_store_id`)
select 2,
       CONCAT('prod_', eav.attribute_code, '_',  s.code) as bizCloud, 
       CONCAT(eav.attribute_code, '|', s.store_id) as magentoCode, 
       eav.attribute_id,
       s.store_id
from eav_attribute eav,
core_store s
where eav.entity_type_id IN (select entity_type_id FROM eav_entity_type WHERE entity_type_code = 'catalog_product')
and eav.backend_type <> 'static'
UNION ALL
select 2,
       CONCAT('prod_', eav.attribute_code) as bizCloud, 
       eav.attribute_code as magentoCode, 
       eav.attribute_id,
       0
from eav_attribute eav
where eav.entity_type_id IN (select entity_type_id FROM eav_entity_type WHERE entity_type_code = 'catalog_product')
and eav.backend_type = 'static';