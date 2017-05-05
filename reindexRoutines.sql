delimiter //

-- reindex stock
DROP PROCEDURE IF EXISTS mmc_reindexStock //
CREATE PROCEDURE mmc_reindexStock ( p_productId INT, p_websiteId INT )
BEGIN
	INSERT INTO cataloginventory_stock_status 
					(product_id,
					website_id,
					stock_id,
					qty,
					stock_status)
	SELECT p_productId, p_websiteId, i.stock_id, i.qty, i.is_in_stock
      FROM cataloginventory_stock_item i
     WHERE i.product_id =  p_productId;
END //

-- reindex price


-- reindex catalog product flat
DROP PROCEDURE IF EXISTS mmc_updateProductFlat //
CREATE PROCEDURE mmc_updateProductFlat ( p_productId INT, p_storeId INT, p_attributeCode VARCHAR(255), p_attributeValue VARCHAR(255), p_attributeValueText TEXT )
outer_block:BEGIN
	DECLARE v_storeId INT;
    DECLARE v_tableExists INT;
    DECLARE v_fieldExists INT;
    DECLARE done INT DEFAULT FALSE;
    DECLARE c_stores CURSOR FOR SELECT store_id FROM core_store WHERE store_id = p_storeId UNION SELECT null; -- WHERE store_id = p_storeId;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET done = TRUE;
    
    OPEN c_stores;    
    
    read_loop: LOOP
		FETCH c_stores INTO v_storeId;
        
        IF done = TRUE or v_storeId IS NULL THEN
			LEAVE read_loop;
		END IF;
        
        -- ITERATE read_loop;
                
		-- check if table exists
		SELECT COUNT(*) INTO v_tableExists
		FROM information_schema.tables 
		WHERE table_schema = 'denimio_live' 
		AND table_name = CONCAT('catalog_product_flat_',v_storeId);
        
        -- continue to next store if flat does not exists for current store
        IF v_tableExists = 0 THEN
			ITERATE read_loop;
        END IF;
        
        -- check if field exists
        SELECT COUNT(*) INTO v_fieldExists
		FROM information_schema.columns 
		WHERE table_schema = 'denimio_live' 
		AND table_name = CONCAT('catalog_product_flat_',v_storeId)
        AND column_name = p_attributeCode;
        
        IF v_fieldExists = 0 THEN
			ITERATE read_loop;
        END IF;
        
        SET @tableName = CONCAT('catalog_product_flat_', v_storeId);
        SET @columnName = p_attributeCode;
        SET @attributeValue = p_attributeValue;
        SET @productId = p_productId;
        SET @queryStmt = CONCAT('UPDATE ',@tableName,' SET ' , @columnName, ' = ? WHERE entity_id = ', @productId);
        PREPARE stmtUpdate FROM @queryStmt;
        EXECUTE stmtUpdate USING @attributeValue;
        
        -- check if field exists
        SELECT COUNT(*) INTO v_fieldExists
		FROM information_schema.columns 
		WHERE table_schema = 'denimio_live' 
		AND table_name = CONCAT('catalog_product_flat_',v_storeId)
        AND column_name = CONCAT(p_attributeCode,'_value');
        
        IF v_fieldExists = 0 THEN
			ITERATE read_loop;
        END IF;
        
        SET @tableName = CONCAT('catalog_product_flat_', v_storeId);
        SET @columnName = CONCAT(p_attributeCode,'_value');
        SET @attributeValue = p_attributeValue;
        SET @productId = p_productId;
        SET @queryStmt = CONCAT('UPDATE ',@tableName,' SET ' , @columnName, ' = ? WHERE entity_id = ', @productId);
        PREPARE stmtUpdate FROM @queryStmt;
        EXECUTE stmtUpdate USING @attributeValue;
        
        
	END LOOP;
    
    CLOSE c_stores;
	
END //

-- reindex catalog product price
DROP PROCEDURE IF EXISTS mmc_reindexProductPrice //
CREATE PROCEDURE mmc_reindexProductPrice ( p_productId INT )
BEGIN
	
    SET @statusAttributeId = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'status' and entity_type_id = 4);
    SET @taxClassIdAttributeId = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'tax_class_id' and entity_type_id = 4);
    SET @priceAttributeId = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'price' and entity_type_id = 4);
    SET @specialPriceAttributeId = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'special_price' and entity_type_id = 4);
    SET @specialFromDateAttributeId = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'special_from_date' and entity_type_id = 4);
    SET @specialToDateAttributeId = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'special_to_date' and entity_type_id = 4);
    
    SELECT type_id INTO @productTypeId
      FROM catalog_product_entity
     WHERE entity_id = p_productId;
    
    CASE @productTypeId
		WHEN 'simple' THEN
			BEGIN
				INSERT INTO catalog_product_index_price (entity_id, 
														 customer_group_id,
                                                         website_id,
                                                         tax_class_id,
                                                         price,
                                                         final_price,
                                                         min_price,
                                                         max_price,
                                                         tier_price,
                                                         group_price)
				SELECT `e`.`entity_id`, 
					   `cg`.`customer_group_id`, 
                       `cw`.`website_id`, 
                       IF(IFNULL(tas_tax_class_id.value_id, -1) > 0, tas_tax_class_id.value, tad_tax_class_id.value) AS `tax_class_id`, ta_price.value AS `orig_price`, 
                       IF(IF(gp.price IS NULL, ta_price.value, gp.price) < IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value), IF(gp.price IS NULL, ta_price.value, gp.price), IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value)) AS `price`, 
                       IF(IF(gp.price IS NULL, ta_price.value, gp.price) < IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value), IF(gp.price IS NULL, ta_price.value, gp.price), IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value)) AS `min_price`, 
                       IF(IF(gp.price IS NULL, ta_price.value, gp.price) < IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value), IF(gp.price IS NULL, ta_price.value, gp.price), IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value)) AS `max_price`, 
                       tp.min_price AS `tier_price`,
                       gp.price AS `group_price` 
				  FROM `catalog_product_entity` AS `e`
				 CROSS JOIN `customer_group` AS `cg`
				 CROSS JOIN `core_website` AS `cw`
				 INNER JOIN `catalog_product_index_website` AS `cwd` ON cw.website_id = cwd.website_id
				 INNER JOIN `core_store_group` AS `csg` ON csg.website_id = cw.website_id AND cw.default_group_id = csg.group_id
				 INNER JOIN `core_store` AS `cs` ON csg.default_store_id = cs.store_id AND cs.store_id != 0
				 INNER JOIN `catalog_product_website` AS `pw` ON pw.product_id = e.entity_id AND pw.website_id = cw.website_id
				 LEFT JOIN `catalog_product_index_tier_price` AS `tp` ON tp.entity_id = e.entity_id AND tp.website_id = cw.website_id AND tp.customer_group_id = cg.customer_group_id
				 LEFT JOIN `catalog_product_index_group_price` AS `gp` ON gp.entity_id = e.entity_id AND gp.website_id = cw.website_id AND gp.customer_group_id = cg.customer_group_id
				 INNER JOIN `catalog_product_entity_int` AS `tad_status` ON tad_status.entity_id = e.entity_id AND tad_status.attribute_id = @statusAttributeId AND tad_status.store_id = 0
				 LEFT JOIN `catalog_product_entity_int` AS `tas_status` ON tas_status.entity_id = e.entity_id AND tas_status.attribute_id = @statusAttributeId AND tas_status.store_id = cs.store_id
				 LEFT JOIN `catalog_product_entity_int` AS `tad_tax_class_id` ON tad_tax_class_id.entity_id = e.entity_id AND tad_tax_class_id.attribute_id = @taxClassIdAttributeId AND tad_tax_class_id.store_id = 0
				 LEFT JOIN `catalog_product_entity_int` AS `tas_tax_class_id` ON tas_tax_class_id.entity_id = e.entity_id AND tas_tax_class_id.attribute_id = @taxClassIdAttributeId AND tas_tax_class_id.store_id = cs.store_id
				 LEFT JOIN `catalog_product_entity_decimal` AS `ta_price` ON ta_price.entity_id = e.entity_id AND ta_price.attribute_id = @priceAttributeId AND ta_price.store_id = 0
				 LEFT JOIN `catalog_product_entity_decimal` AS `ta_special_price` ON ta_special_price.entity_id = e.entity_id AND ta_special_price.attribute_id = @specialPriceAttributeId AND ta_special_price.store_id = 0
				 LEFT JOIN `catalog_product_entity_datetime` AS `tad_special_from_date` ON tad_special_from_date.entity_id = e.entity_id AND tad_special_from_date.attribute_id = @specialFromDateAttributeId AND tad_special_from_date.store_id = 0
				 LEFT JOIN `catalog_product_entity_datetime` AS `tas_special_from_date` ON tas_special_from_date.entity_id = e.entity_id AND tas_special_from_date.attribute_id = @specialFromDateAttributeId AND tas_special_from_date.store_id = cs.store_id
				 LEFT JOIN `catalog_product_entity_datetime` AS `tad_special_to_date` ON tad_special_to_date.entity_id = e.entity_id AND tad_special_to_date.attribute_id = @specialToDateAttributeId AND tad_special_to_date.store_id = 0
				 LEFT JOIN `catalog_product_entity_datetime` AS `tas_special_to_date` ON tas_special_to_date.entity_id = e.entity_id AND tas_special_to_date.attribute_id = @specialToDateAttributeId AND tas_special_to_date.store_id = cs.store_id
				 INNER JOIN `cataloginventory_stock_status` AS `ciss` ON ciss.product_id = e.entity_id AND ciss.website_id = cw.website_id 
				 WHERE (e.type_id = 'simple') 
				 AND (IF(IFNULL(tas_status.value_id, -1) > 0, tas_status.value, tad_status.value)=1) 
				 AND (e.entity_id IN(p_productId)) AND (ciss.stock_status = 1)
                 ON DUPLICATE KEY UPDATE tax_class_id = VALUES(`tax_class_id`),
										 price = VALUES(`price`),
										 final_price = VALUES(`final_price`),
                                         min_price = VALUES(`min_price`),
                                         max_price = VALUES(`max_price`),
										 tier_price = VALUES(`tier_price`),
										 group_price = VALUES(`group_price`);
            END;
        WHEN 'configurable' THEN
			INSERT INTO catalog_product_index_price (entity_id, 
														 customer_group_id,
                                                         website_id,
                                                         tax_class_id,
                                                         price,
                                                         final_price,
                                                         min_price,
                                                         max_price,
                                                         tier_price,
                                                         group_price)
			SELECT `e`.`entity_id`, 
					`cg`.`customer_group_id`, 
                    `cw`.`website_id`, 
                    IF(IFNULL(tas_tax_class_id.value_id, -1) > 0, tas_tax_class_id.value, tad_tax_class_id.value) AS `tax_class_id`, 
                    ta_price.value AS `orig_price`, 
                    IF(IF(gp.price IS NULL, ta_price.value, gp.price) < IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value), IF(gp.price IS NULL, ta_price.value, gp.price), IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value)) AS `price`, 
                    IF(IF(gp.price IS NULL, ta_price.value, gp.price) < IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value), IF(gp.price IS NULL, ta_price.value, gp.price), IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value)) AS `min_price`, 
                    IF(IF(gp.price IS NULL, ta_price.value, gp.price) < IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value), IF(gp.price IS NULL, ta_price.value, gp.price), IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND ta_special_price.value < ta_price.value, ta_special_price.value, ta_price.value)) AS `max_price`, 
                    tp.min_price AS `tier_price`, 
                    gp.price AS `group_price` 
			   FROM `catalog_product_entity` AS `e`
			 CROSS JOIN `customer_group` AS `cg`
			 CROSS JOIN `core_website` AS `cw`
			 INNER JOIN `catalog_product_index_website` AS `cwd` ON cw.website_id = cwd.website_id
			 INNER JOIN `core_store_group` AS `csg` ON csg.website_id = cw.website_id AND cw.default_group_id = csg.group_id
			 INNER JOIN `core_store` AS `cs` ON csg.default_store_id = cs.store_id AND cs.store_id != 0
			 INNER JOIN `catalog_product_website` AS `pw` ON pw.product_id = e.entity_id AND pw.website_id = cw.website_id
			 LEFT JOIN `catalog_product_index_tier_price` AS `tp` ON tp.entity_id = e.entity_id AND tp.website_id = cw.website_id AND tp.customer_group_id = cg.customer_group_id
			 LEFT JOIN `catalog_product_index_group_price` AS `gp` ON gp.entity_id = e.entity_id AND gp.website_id = cw.website_id AND gp.customer_group_id = cg.customer_group_id
			 INNER JOIN `catalog_product_entity_int` AS `tad_status` ON tad_status.entity_id = e.entity_id AND tad_status.attribute_id = @statusAttributeId AND tad_status.store_id = 0
			 LEFT JOIN `catalog_product_entity_int` AS `tas_status` ON tas_status.entity_id = e.entity_id AND tas_status.attribute_id = @statusAttributeId AND tas_status.store_id = cs.store_id
			 LEFT JOIN `catalog_product_entity_int` AS `tad_tax_class_id` ON tad_tax_class_id.entity_id = e.entity_id AND tad_tax_class_id.attribute_id = @taxClassIdAttributeId AND tad_tax_class_id.store_id = 0
			 LEFT JOIN `catalog_product_entity_int` AS `tas_tax_class_id` ON tas_tax_class_id.entity_id = e.entity_id AND tas_tax_class_id.attribute_id = @taxClassIdAttributeId AND tas_tax_class_id.store_id = cs.store_id
			 LEFT JOIN `catalog_product_entity_decimal` AS `ta_price` ON ta_price.entity_id = e.entity_id AND ta_price.attribute_id = @priceAttributeId AND ta_price.store_id = 0
			 LEFT JOIN `catalog_product_entity_decimal` AS `ta_special_price` ON ta_special_price.entity_id = e.entity_id AND ta_special_price.attribute_id = @specialPriceAttributeId AND ta_special_price.store_id = 0
			 LEFT JOIN `catalog_product_entity_datetime` AS `tad_special_from_date` ON tad_special_from_date.entity_id = e.entity_id AND tad_special_from_date.attribute_id = @specialFromDateAttributeId AND tad_special_from_date.store_id = 0
			 LEFT JOIN `catalog_product_entity_datetime` AS `tas_special_from_date` ON tas_special_from_date.entity_id = e.entity_id AND tas_special_from_date.attribute_id = @specialFromDateAttributeId AND tas_special_from_date.store_id = cs.store_id
			 LEFT JOIN `catalog_product_entity_datetime` AS `tad_special_to_date` ON tad_special_to_date.entity_id = e.entity_id AND tad_special_to_date.attribute_id = @specialToDateAttributeId AND tad_special_to_date.store_id = 0
			 LEFT JOIN `catalog_product_entity_datetime` AS `tas_special_to_date` ON tas_special_to_date.entity_id = e.entity_id AND tas_special_to_date.attribute_id = @specialToDateAttributeId AND tas_special_to_date.store_id = cs.store_id
			 INNER JOIN `cataloginventory_stock_status` AS `ciss` ON ciss.product_id = e.entity_id AND ciss.website_id = cw.website_id 
			 WHERE (e.type_id = 'configurable') 
			 AND (IF(IFNULL(tas_status.value_id, -1) > 0, tas_status.value, tad_status.value)=1) 
			 -- AND (e.entity_id IN(875)) 
			 AND (ciss.stock_status = 1)
             ON DUPLICATE KEY UPDATE tax_class_id = VALUES(`tax_class_id`),
										 price = VALUES(`price`),
										 final_price = VALUES(`final_price`),
                                         min_price = VALUES(`min_price`),
                                         max_price = VALUES(`max_price`),
										 tier_price = VALUES(`tier_price`),
										 group_price = VALUES(`group_price`);
        ELSE
			BEGIN
            END;
    end case;
END //