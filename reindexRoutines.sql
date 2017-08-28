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
    
-- reinde stock for all websites product is associated    
DROP PROCEDURE IF EXISTS mmc_reindexStockAllWeb //
CREATE PROCEDURE mmc_reindexStockAllWeb ( p_productId INT )
BEGIN

	SET @statusAttributeId = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'status' and entity_type_id = 4);

	INSERT INTO cataloginventory_stock_status (product_id, website_id, stock_id, qty, stock_status)
    SELECT `e`.`entity_id`, 
			`cw`.`website_id`, 
            `cis`.`stock_id`, 
            IF(cisi.qty > 0, cisi.qty, 0) AS `qty`, 
            -- IF(cisi.use_config_manage_stock = 0 AND cisi.manage_stock = 0, 1, IF(cisi.backorders = 30, 1, cisi.is_in_stock)) AS `status` 
            -- IF(IF(IFNULL(tas_status.value_id, -1) > 0, tas_status.value, tad_status.value)=1, 1, 0) as `status` -- stock_status is available if product is enabled
            `cisi`.`is_in_stock` as `status`
      FROM `catalog_product_entity` AS `e`
	 CROSS JOIN `core_website` AS `cw`
	 INNER JOIN `core_store_group` AS `csg` ON csg.group_id = cw.default_group_id
	 INNER JOIN `core_store` AS `cs` ON cs.store_id = csg.default_store_id
	 INNER JOIN `catalog_product_website` AS `pw` ON pw.product_id = e.entity_id AND pw.website_id = cw.website_id
	 CROSS JOIN `cataloginventory_stock` AS `cis`
	 LEFT JOIN `cataloginventory_stock_item` AS `cisi` ON cisi.stock_id = cis.stock_id AND cisi.product_id = e.entity_id
	 INNER JOIN `catalog_product_entity_int` AS `tad_status` ON tad_status.entity_id = e.entity_id AND tad_status.attribute_id = @statusAttributeId AND tad_status.store_id = 0
	 LEFT JOIN `catalog_product_entity_int` AS `tas_status` ON tas_status.entity_id = e.entity_id AND tas_status.attribute_id = @statusAttributeId AND tas_status.store_id = cs.store_id 
	 WHERE (cw.website_id != 0) 
       AND (e.type_id = 'simple') 
       AND (IF(IFNULL(tas_status.value_id, -1) > 0, tas_status.value, tad_status.value)=1) 
       AND (e.entity_id IN(p_productId))
    ON DUPLICATE KEY UPDATE `qty` = VALUES(`qty`), stock_status = VALUES(`stock_status`);
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
    DECLARE c_stores CURSOR FOR SELECT cs.store_id 
								  FROM core_store cs,
									   catalog_product_website cpw
								 WHERE cs.website_id = cpw.website_id
								   AND cpw.product_id = p_productId
                                   AND IF(p_storeId, IF(p_storeId=cs.store_id,1,0) ,1) = 1
								UNION 
                                SELECT null; -- WHERE store_id = p_storeId;
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
		WHERE table_schema = 'magento_hd' 
		AND table_name = CONCAT('catalog_product_flat_',v_storeId);
        
        -- continue to next store if flat does not exists for current store
        IF v_tableExists = 0 THEN
			ITERATE read_loop;
        END IF;
        
        -- check if field exists
        SELECT COUNT(*) INTO v_fieldExists
		FROM information_schema.columns 
		WHERE table_schema = 'magento_hd' 
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
        
        DEALLOCATE prepare stmtUpdate;
        
	END LOOP;
    
    CLOSE c_stores;
	
END //

DROP PROCEDURE IF EXISTS mmc_updateProductFlatBulk //
CREATE PROCEDURE mmc_updateProductFlatBulk ( p_productId INT, p_recordId )
outer_block:BEGIN
	DECLARE v_storeId INT;
    DECLARE v_tableExists INT;
    DECLARE v_fieldExists INT;
    DECLARE done INT DEFAULT FALSE;
    DECLARE c_stores CURSOR FOR SELECT cs.store_id 
								  FROM core_store cs,
									   catalog_product_website cpw
								 WHERE cs.website_id = cpw.website_id
								   AND cpw.product_id = p_productId
                                   AND IF(p_storeId, IF(p_storeId=cs.store_id,1,0) ,1) = 1
								UNION 
                                SELECT null; -- WHERE store_id = p_storeId;
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
		WHERE table_schema = 'magento_hd' 
		AND table_name = CONCAT('catalog_product_flat_',v_storeId);
        
        -- continue to next store if flat does not exists for current store
        IF v_tableExists = 0 THEN
			ITERATE read_loop;
        END IF;
        
        -- check if field exists
        SELECT COUNT(*) INTO v_fieldExists
		FROM information_schema.columns 
		WHERE table_schema = 'magento_hd' 
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
        
        DEALLOCATE prepare stmtUpdate;
        
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
     
    -- prepare group price index
    INSERT INTO `catalog_product_index_group_price` (`entity_id`, `customer_group_id`, `website_id`, `price`)
	SELECT `gp`.`entity_id`, 
		   `cg`.`customer_group_id`, 
		   `cw`.`website_id`, 
		   MIN(IF(gp.website_id = 0, ROUND(gp.value * cwd.rate, 4), gp.value)) 
	  FROM `catalog_product_entity_group_price` AS `gp`
	 INNER JOIN `customer_group` AS `cg` ON gp.all_groups = 1 OR (gp.all_groups = 0 AND gp.customer_group_id = cg.customer_group_id)
	 INNER JOIN `core_website` AS `cw` ON gp.website_id = 0 OR gp.website_id = cw.website_id
	 INNER JOIN `catalog_product_index_website` AS `cwd` ON cw.website_id = cwd.website_id 
	 WHERE (cw.website_id != 0) 
	   AND (gp.entity_id IN(p_productId)) 
	GROUP BY `gp`.`entity_id`,
		`cg`.`customer_group_id`,
		`cw`.`website_id` 
	ON DUPLICATE KEY UPDATE `price` = VALUES(`price`);
    
    -- reindex product price
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
                        IF(IFNULL(tas_tax_class_id.value_id, -1) > 0, tas_tax_class_id.value, tad_tax_class_id.value) AS `tax_class_id`, 
                        IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value) AS `orig_price`, 
                        IF(IF(gp.price IS NULL, IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), gp.price) < IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value) < IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value), IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value)), IF(gp.price IS NULL, IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), gp.price), IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value) < IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value), IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value))) AS `price`, 
                        IF(IF(gp.price IS NULL, IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), gp.price) < IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value) < IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value), IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value)), IF(gp.price IS NULL, IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), gp.price), IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value) < IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value), IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value))) AS `min_price`, 
                        IF(IF(gp.price IS NULL, IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), gp.price) < IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value) < IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value), IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value)), IF(gp.price IS NULL, IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), gp.price), IF(IF(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_from_date.value_id, -1) > 0, tas_special_from_date.value, tad_special_from_date.value)) <= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value) IS NULL, 1, IF(DATE(IF(IFNULL(tas_special_to_date.value_id, -1) > 0, tas_special_to_date.value, tad_special_to_date.value)) >= DATE(cwd.website_date), 1, 0)) > 0 AND IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value) < IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value), IF(IFNULL(tas_special_price.value_id, -1) > 0, tas_special_price.value, tad_special_price.value), IF(IFNULL(tas_price.value_id, -1) > 0, tas_price.value, tad_price.value))) AS `max_price`, 
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
				 LEFT JOIN `catalog_product_entity_decimal` AS `tad_price` ON tad_price.entity_id = e.entity_id AND tad_price.attribute_id = @priceAttributeId AND tad_price.store_id = 0
				 LEFT JOIN `catalog_product_entity_decimal` AS `tas_price` ON tas_price.entity_id = e.entity_id AND tas_price.attribute_id = @priceAttributeId AND tas_price.store_id = cs.store_id
				 LEFT JOIN `catalog_product_entity_decimal` AS `tad_special_price` ON tad_special_price.entity_id = e.entity_id AND tad_special_price.attribute_id = @specialPriceAttributeId AND tad_special_price.store_id = 0
				 LEFT JOIN `catalog_product_entity_decimal` AS `tas_special_price` ON tas_special_price.entity_id = e.entity_id AND tas_special_price.attribute_id = @specialPriceAttributeId AND tas_special_price.store_id = cs.store_id
				 LEFT JOIN `catalog_product_entity_datetime` AS `tad_special_from_date` ON tad_special_from_date.entity_id = e.entity_id AND tad_special_from_date.attribute_id = @specialFromDateAttributeId AND tad_special_from_date.store_id = 0
				 LEFT JOIN `catalog_product_entity_datetime` AS `tas_special_from_date` ON tas_special_from_date.entity_id = e.entity_id AND tas_special_from_date.attribute_id = @specialFromDateAttributeId AND tas_special_from_date.store_id = cs.store_id
				 LEFT JOIN `catalog_product_entity_datetime` AS `tad_special_to_date` ON tad_special_to_date.entity_id = e.entity_id AND tad_special_to_date.attribute_id = @specialToDateAttributeId AND tad_special_to_date.store_id = 0
				 LEFT JOIN `catalog_product_entity_datetime` AS `tas_special_to_date` ON tas_special_to_date.entity_id = e.entity_id AND tas_special_to_date.attribute_id = @specialToDateAttributeId AND tas_special_to_date.store_id = cs.store_id
				 INNER JOIN `cataloginventory_stock_status` AS `ciss` ON ciss.product_id = e.entity_id AND ciss.website_id = cw.website_id 
                 WHERE (e.type_id = 'simple') 
                 AND (IF(IFNULL(tas_status.value_id, -1) > 0, tas_status.value, tad_status.value)=1) 
                 AND (e.entity_id IN(p_productId)) 
                 ON DUPLICATE KEY UPDATE tax_class_id = VALUES(`tax_class_id`),
										 price = VALUES(`price`),
										 final_price = VALUES(`final_price`),
                                         min_price = VALUES(`min_price`),
                                         max_price = VALUES(`max_price`),
										 tier_price = VALUES(`tier_price`),
										 group_price = VALUES(`group_price`);
							
            END;
        ELSE
			BEGIN
            END;
    end case;
END //