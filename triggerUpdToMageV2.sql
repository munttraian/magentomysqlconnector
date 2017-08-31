delimiter //
-- get magento attribute code based on bizcloud fieldname
DROP FUNCTION IF EXISTS getMagentoField //
CREATE FUNCTION getMagentoField ( bizField VARCHAR(255) ) RETURNS VARCHAR(255) deterministic
BEGIN
	-- SET @fieldMagento = (SELECT magento_field_name FROM magento_field_matches WHERE cloud_biz_field_name = bizField);
    -- SET @fieldMagento = (SELECT IF(INSTR(magento_field_name,'|'), SUBSTRING_INDEX(magento_field_name,'|', 1), magento_field_name) FROM magento_field_matches WHERE cloud_biz_field_name = bizField);

	SET @fieldMagento = (SELECT IF(INSTR(bizField,'|'), SUBSTRING_INDEX(bizField,'|', 1), bizField));
    
    RETURN @fieldMagento;
END //

-- get magento store id
DROP FUNCTION IF EXISTS getMagentoFieldStore //
CREATE FUNCTION getMagentoFieldStore ( bizField VARCHAR(255) ) RETURNS VARCHAR(255) deterministic
BEGIN
	-- SET @fieldMagentoStore = (SELECT IF(INSTR(magentofield_id_magento,'|'), SUBSTRING_INDEX(magentofield_id_magento,'|',-1), 0) FROM magento_field_matches WHERE field_id_biz_cloud = bizField);
    -- SET @fieldMagentoStore = (SELECT magento_store_id FROM magento_field_matches WHERE cloud_biz_field_name = bizField);
    
    SET @fieldMagentoStore = (SELECT IF(INSTR(bizField,'|'), SUBSTRING_INDEX(bizField,'|',-1), 0));
    
    -- IF @fieldMagentoStore IS NULL OR @fieldMagentoStore = '' THEN
	-- 	SET @fieldMagentoStore = 0;
    -- END IF;
    
    RETURN @fieldMagentoStore;
END //

-- log message in table
DROP PROCEDURE IF EXISTS logMessage //
CREATE PROCEDURE logMessage ( IN message TEXT ) 
BEGIN
	INSERT INTO `bizcloud_magento_log` (`text`) VALUES (message);
END //

-- get attributes used in configurable products
DROP FUNCTION IF EXISTS getConfigurableAttributes //
CREATE FUNCTION getConfigurableAttributes( p_attributeSetId VARCHAR(255) ) RETURNS VARCHAR(255) reads sql data
BEGIN
	DECLARE v_attributes VARCHAR(255);
    
	SELECT group_concat(c.attribute_id SEPARATOR ',')
      INTO v_attributes
	  FROM catalog_eav_attribute c, 
           eav_entity_attribute a,
           eav_attribute e
     WHERE c.is_configurable = 1
       AND c.is_global = 1
       AND c.attribute_id = a.attribute_id
       AND a.attribute_set_id = p_attributeSetId
       AND c.attribute_id = e.attribute_id
       AND e.frontend_input = 'select';
	
    RETURN v_attributes;
END //

-- count charcter occurence in text
DROP FUNCTION IF EXISTS countOccurence //
CREATE FUNCTION countOccurence ( p_text TEXT, p_needle VARCHAR(255) ) RETURNS int deterministic
BEGIN
	DECLARE noOccur INT;
    
    SELECT ROUND (   
        (
            LENGTH(p_text)
            - LENGTH( REPLACE ( p_text, p_needle, "") ) 
        ) / LENGTH(p_neddle)        
    ) AS count
    INTO noOccur;
    
    RETURN noOccur;
END //

-- get element by index from a set like 'a,b,cc,ddf,eee'
DROP FUNCTION IF EXISTS getSetElementByIndex //
CREATE FUNCTION getSetElementByIndex ( p_settext TEXT, p_ind INT) RETURNS varchar(255) deterministic
BEGIN
	DECLARE v_element VARCHAR(255);
    
    SELECT substring_index(substring_index(p_settext, ',', p_ind), ',', -1)
    INTO v_element;

	RETURN v_element;
END //

-- create stock line
DROP PROCEDURE IF EXISTS addStockLine //
CREATE PROCEDURE addStockLine( p_productId int, p_websiteIds TEXT) modifies sql data
BEGIN
	
    INSERT IGNORE INTO cataloginventory_stock_item (product_id, stock_id, qty, is_in_stock)
    VALUES (p_productId, 1, 0, 0);
    
    INSERT IGNORE INTO cataloginventory_stock_status (`product_id`, `website_id`, `stock_id`, `qty`, `stock_status`)
    SELECT p_productId, w.website_id, 1, 0, 0
      FROM core_website w
     WHERE FIND_IN_SET(w.website_id, p_websiteIds); 
    
END //

-- check if customer address exists
DROP FUNCTION IF EXISTS checkCustomerAddress //
CREATE FUNCTION checkCustomerAddress ( p_recordId int, p_addressType VARCHAR(255)) RETURNS INT
BEGIN
    DECLARE v_return INT;
    DECLARE v_address TEXT;
    DECLARE v_entity_id INT(10);
    DECLARE v_entity_type_id INT;
    
    SET v_entity_type_id = (SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code = 'customer_address');
    
    SET v_return = 0;
    SET v_entity_id = 0;
    
    SET sql_mode = '';

	SET @addressConcat = (
		SELECT group_concat(field_value order by eav.attribute_id ASC SEPARATOR ',')
		  FROM to_magento_datas tmd
          JOIN eav_attribute eav ON REPLACE(tmd.field_name,p_addressType,'') = eav.attribute_code
         WHERE tmd.record_id = p_recordId
           AND REPLACE(tmd.field_name,p_addressType,'') IN ('firstname', 'lastname')
           AND eav.entity_type_id = v_entity_type_id
           AND (INSTR(tmd.field_name, 'addr_bll') = 1 OR INSTR(tmd.field_name, 'addr_dlv') = 1)
        GROUP BY tmd.record_id
        ORDER BY attribute_id ASC
		);
        
    SELECT t.entity_id, group_concat(t.value order by t.attribute_id ASC SEPARATOR ',')
      INTO v_entity_id, v_address
      FROM (
			SELECT entity_id, attribute_id, value
			  FROM customer_address_entity_int
			UNION ALL 
			SELECT entity_id, attribute_id, value 
			  FROM customer_address_entity_varchar
			UNION ALL
			SELECT entity_id, attribute_id, value
			  FROM customer_address_entity_text
			UNION ALL
			SELECT entity_id, attribute_id, value
			  FROM customer_address_entity_decimal
			UNION ALL
			SELECT entity_id, attribute_id, value
			  FROM customer_address_entity_datetime
			) t
     WHERE t.attribute_id 
			IN (SELECT attribute_id 
				  FROM eav_attribute 
                 WHERE entity_type_id = v_entity_type_id 
                   AND attribute_code IN ('firstname', 'lastname')
				)
    GROUP BY t.entity_id
    HAVING group_concat(t.value order by t.attribute_id ASC SEPARATOR ',') = @addressConcat
    LIMIT 1;
    
    RETURN v_entity_id;

END //

DROP TRIGGER IF EXISTS triggerUpdToMage //
CREATE TRIGGER triggerUpdToMage BEFORE UPDATE ON to_magento_records
FOR EACH ROW
outer_block:BEGIN
	
    SET NAMES 'utf8' COLLATE 'utf8_unicode_ci';

	IF NEW.status = 1 THEN
		SET NEW.status = 2; 
		
		-- category
		IF new.type = 1 THEN
			SET NEW.message = 'update category';
			
			-- get category id
			SET @categoryid = NEW.identifier;
			
			-- get action
			SET @action = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'action' );
			
			IF @action = '' THEN
				SET NEW.message = 'Action field not set';
                SET NEW.status = 3;
				LEAVE outer_block;
			END IF;
            
            -- get basic category data
			SET @entity_id = IF(@categoryid=0,NULL,@categoryid);
			SET @entity_type_id = (SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code = 'catalog_category');
			SET @attribute_set_id = 3;
			SET @path = CONCAT('1/', @categoryid);
			SET @parent_id = 1;
			
            -- treat delete action
            IF @action = 2 THEN
				SET NEW.message = 'Delete category';
				DELETE FROM catalog_category_entity WHERE entity_id = @entity_id;
                LEAVE outer_block;
            END IF;
            
            -- treat create/update action
			INSERT IGNORE INTO catalog_category_entity (`entity_id`,`entity_type_id`, `attribute_set_id`) -- , `path`, `parent_id`)
			VALUES (@entity_id, @entity_type_id, @attribute_set_id); -- , @path, @parent_id)
			-- ON DUPLICATE KEY UPDATE `path` = VALUES(`path`);
		
            
            -- if new category id update category id
			IF @categoryid = 0 THEN 
                SET @categoryid = LAST_INSERT_ID(); 
                SET NEW.identifier = @categoryid;
			END IF;
            
            -- update boolean values like Yes/No Ja/Nein
            UPDATE to_magento_datas
               SET field_value = 1
             WHERE record_id = NEW.record_id
               AND field_value IN ('Yes','Ja');
			
            UPDATE to_magento_datas
               SET field_value = 0
             WHERE record_id = NEW.record_id
               AND field_value IN ('No','Nein');
            
			-- varchar
            INSERT INTO catalog_category_entity_varchar (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @category_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'varchar'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- int
            INSERT INTO catalog_category_entity_int (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @category_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'int'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- decimal
            INSERT INTO catalog_category_entity_decimal (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @category_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'decimal'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- text
            INSERT INTO catalog_category_entity_text (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @category_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'text'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
               
            -- datetime
            INSERT INTO catalog_category_entity_text (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @category_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'datetime'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);   
            
            -- update path based on parent id
            -- SET @parent_id = (SELECT parent_id FROM catalog_category_entity WHERE entity_id = @category_id);
            -- SET @parent_path = (SELECT path FROM catalog_category_entity WHERE entity_id = @parent_id);
            
            -- UPDATE catalog_category_entity
            --    SET path = CONCAT(@parent_path,'/',@category_id)
             -- WHERE entity_id = @category_id;  
						
		END IF;
		
        
        -- -------------------------------------------------------------- --
        -- -------------------- PRODUCT PART ---------------------------- --
		IF new.type = 2 THEN
			
            SET NEW.message = 'update product - start';
            
            SET @sku = NEW.identifier;
            
            -- get action
			SET @action = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'action' );
			SET @type_id = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'prod_type_id' );
			SET @product_id = (SELECT entity_id FROM catalog_product_entity WHERE sku = @sku);
			SET @productCategoryIds  = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'categories_ids' );
            -- SET @productWebsiteIds  = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'prod_website_ids' );
			SET @productWebsiteIds  = (SELECT group_concat(s.website_id SEPARATOR ',') 
										 FROM to_magento_datas tmd,
											  core_store s
                                        WHERE tmd.record_id = NEW.record_id 
                                          AND tmd.field_name LIKE 'sku|%' 
                                          AND IF(INSTR(tmd.field_name,'|'), SUBSTRING_INDEX(tmd.field_name,'|',-1), 0) = s.store_id
										);
            SET @attribute_set_id = (SELECT field_value FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'attributesetid');
			SET @entity_type_id = (SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code = 'catalog_product');
        
            -- check if action set
			IF @action = '' THEN
				SET NEW.message = 'Action field not set';
                SET NEW.status = 3;
				LEAVE outer_block;
			END IF;
            
            -- check if sku set
            IF @sku = '' THEN
				SET NEW.message = 'Sku field not set';
                SET NEW.status = 3;
				LEAVE outer_block;
			END IF;
            
            -- check if type_id set
            -- if not assume type_id = simple
            IF @type_id = '' OR @type_id IS NULL THEN
				SET @type_id = 'simple';
            END IF;
            
            -- get basic product data
			SET @entity_id = IF(@product_id=0,NULL,@product_id);
			-- SET @entity_type_id = 4;

			-- if no attribute set id -> get default
            IF @attribute_set_id IS NULL THEN
				SET @attribute_set_id = (SELECT attribute_set_id FROM eav_attribute_set WHERE entity_type_id = @entity_type_id AND attribute_set_name = 'Default');
            END IF;
			
            -- treat delete action
            IF @action = 2 THEN
				SET NEW.message = 'Delete product';
				DELETE FROM catalog_product_entity WHERE entity_id = @entity_id;
                LEAVE outer_block;
            END IF; 
            
            
            -- if new product update product id
			IF !@product_id OR @product_id IS NULL OR @product_id = '' THEN 
				-- treat create/update action
				INSERT INTO catalog_product_entity (`entity_id`,`entity_type_id`, `attribute_set_id`, `type_id`, `sku`, `has_options`, `required_options`, `created_at`, `updated_at`)
				VALUES (NULL, @entity_type_id, @attribute_set_id, @type_id, @sku, 0, 0, now(), now())
				ON DUPLICATE KEY UPDATE `updated_at` = VALUES(`updated_at`);
                
				SET @product_id = LAST_INSERT_ID(); 
                
                SET @entity_id = @product_id;
                -- SET NEW.identifier = @product_id;
            ELSE
				UPDATE catalog_product_entity
                   SET attribute_set_id = @attribute_set_id
                 WHERE entity_id = @product_id;  
			END IF;
            
            -- ADD DEFAULT DATA for visibility and status
            -- visiblity
            SET @visibilityExists = 0;
            SELECT 1 INTO @visibilityExists FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name LIKE 'visibility|0' LIMIT 1;
            
            IF @visibilityExists = 0 THEN
				INSERT INTO to_magento_datas (record_id, field_name, field_value) VALUES (NEW.record_id, 'visibility|0', 4);
            END IF;
            
            -- status
            SET @statusExists = 0;
            SELECT 1 INTO @statusExists FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name LIKE 'status%' LIMIT 1;
            
            IF @statusExists = 0 THEN
				INSERT INTO to_magento_datas (record_id, field_name, field_value) VALUES (NEW.record_id, 'status|0', 2);
            END IF;
            
            -- tax_class_id
            SET @taxClassIdExists = 0;
            SELECT 1 INTO @taxClassIdExists FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name LIKE 'tax_class_id|0' LIMIT 1;
            
            IF @taxClassIdExists = 0 THEN
				INSERT INTO to_magento_datas (record_id, field_name, field_value) VALUES (NEW.record_id, 'tax_class_id|0', 2);
            END IF;
            
            
            SET NEW.message = 'START PRODUCT IMPORT';
            
            -- update boolean values like Yes/No Ja/Nein
            UPDATE to_magento_datas
               SET field_value = 1
             WHERE record_id = NEW.record_id
               AND field_value IN ('Yes','Ja');
			
            UPDATE to_magento_datas
               SET field_value = 0
             WHERE record_id = NEW.record_id
               AND field_value IN ('No','Nein');
            
            UPDATE to_magento_datas
               SET field_name = REPLACE(field_name,'designid','custom_design')
             WHERE record_id = NEW.record_id
               AND field_name LIKE 'designid%';
            
            -- update brand value with option_id from magento
            UPDATE to_magento_datas tmd
               SET field_value = (SELECT MIN(eov.option_id) 
									FROM eav_attribute e
                                    JOIN eav_attribute_option eo ON e.attribute_id = eo.attribute_id 
									JOIN eav_attribute_option_value eov ON eov.option_id = eo.option_id
								   WHERE e.attribute_code = 'brand'
                                     AND e.entity_type_id = @entity_type_id
                                     AND eov.value = tmd.field_value
                                     AND eov.store_id = 0
                                 )
             WHERE record_id = NEW.record_id
               AND field_name LIKE 'brand|%'
               AND concat('',field_value * 1) != field_value;
            
            -- varchar
            INSERT INTO catalog_product_entity_varchar (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @product_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'varchar'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- int
            INSERT INTO catalog_product_entity_int (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @product_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'int'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- decimal
            INSERT INTO catalog_product_entity_decimal (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @product_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'decimal'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- text
            INSERT INTO catalog_product_entity_text (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @product_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'text'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
               
            -- datetime
            INSERT INTO catalog_product_entity_text (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|',-1), 0) as store_id, 
                    @product_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'datetime'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);   
            
            -- add products to category
			DELETE FROM catalog_category_product WHERE product_id = @product_id;
                        
			INSERT IGNORE INTO catalog_category_product (category_id, product_id)
			SELECT c.entity_id, @product_id
			  FROM catalog_category_entity c
			 WHERE FIND_IN_SET(c.entity_id, @productCategoryIds); 
             
            -- add products to website
			DELETE FROM catalog_product_website WHERE product_id = @product_id;
            
            INSERT IGNORE INTO catalog_product_website (product_id, website_id)
			SELECT @product_id, w.website_id
			  FROM core_website w
			 WHERE FIND_IN_SET(w.website_id, @productWebsiteIds); 
            
            
            -- add stock line
            CALL addStockLine(@product_id, @productWebsiteIds);
			 
			-- link simple products
			IF @type_id = 'configurable' THEN
				SET @simpleProducts = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'prod_simple_sku' );
				
			END IF;
            
            SET NEW.message = 'END PRODUCT IMPORT';
            
		END IF;
        
        
        -- -------------------------------------------------------------- --
        -- -------------------- STOCK PART START ------------------------ --
        IF new.type = 3 THEN
			SET NEW.message = 'update product stock - start';
            
            SET @sku = NEW.identifier;
            
            SET @product_id = (SELECT entity_id FROM catalog_product_entity WHERE sku = @sku);
            
            SET @qty = (SELECT field_value FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'qty');
            
            SET @statusAttributeId = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'status' and entity_type_id = 4);
            
            -- check if sku is set
            IF @sku = '' THEN
				SET NEW.message = 'Sku field not set';
                SET NEW.status = 3;
				LEAVE outer_block;
			END IF;
            
            IF !@product_id OR @product_id IS NULL OR @product_id = '' THEN 
				SET NEW.message = 'No matching product found for sku';
                SET NEW.status = 3;
				LEAVE outer_block;
            END IF;
            
            -- stock item
            INSERT INTO cataloginventory_stock_item (product_id, stock_id, qty, is_in_stock)
		    SELECT `e`.`entity_id`, 1, @qty, IF(MAX(`tad_status`.value)=1, IF(@qty > 0,1,0) ,0) as `is_in_stock`
            -- SELECT `e`.`entity_id`, 1, @qty, 1 as `is_in_stock`
              FROM `catalog_product_entity` AS `e`
              INNER JOIN `catalog_product_entity_int` AS `tad_status` ON tad_status.entity_id = e.entity_id AND tad_status.attribute_id = @statusAttributeId 
			 WHERE `e`.`entity_id` = @product_id
             GROUP BY `e`.`entity_id`
            ON DUPLICATE KEY UPDATE `qty` = VALUES(`qty`), `is_in_stock` = VALUES(`is_in_stock`);
            
            -- UPDATE cataloginventory_stock_item
            --    SET `qty` = @qty,
			-- 	   `is_in_stock` = IF(@qty > 0,1,0)
            --  WHERE product_id = @product_id;
             
            CALL mmc_reindexStockAllWeb(@product_id);
            CALL mmc_reindexProductPrice(@product_id);
            
            SET NEW.message = 'END STOCK IMPORT';
        END IF;
        
        -- -------------------- STOCK PART END -------------------------- --
        -- -------------------------------------------------------------- --
		
        
        -- -------------------------------------------------------------- --
        -- -------------------- PRICE PART START ------------------------ --
        IF new.type = 4 THEN
        
			SET NEW.message = 'update product price - start';
            
            SET @sku = NEW.identifier;
            
            SET @product_id = (SELECT entity_id FROM catalog_product_entity WHERE sku = @sku);
            
            SET @priceAttributeId = (SELECT attribute_id FROM eav_attribute WHERE attribute_code = 'price' and entity_type_id = 4);
            
            SET @entity_type_id = (SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code = 'catalog_product');
            
            -- check if sku is set
            IF @sku = '' THEN
				SET NEW.message = 'Sku field not set';
                SET NEW.status = 3;
				LEAVE outer_block;
			END IF;
            
            IF !@product_id OR @product_id IS NULL OR @product_id = '' THEN 
				SET NEW.message = 'No matching product found for sku';
                SET NEW.status = 3;
				LEAVE outer_block;
            END IF;
        
            -- insert prices
			INSERT INTO catalog_product_entity_decimal (entity_type_id, entity_id, attribute_id, store_id, value)
            SELECT @entity_type_id, @product_id, @priceAttributeId, csg.default_store_id, tmd.field_value
			  FROM to_magento_datas tmd,
                   hd_pricegroup_website hpw,
                   core_store_group csg
             WHERE tmd.record_id = new.record_id
               AND tmd.field_name = hpw.pricegroup
               AND csg.website_id = hpw.website_id
               AND hpw.special = 0
            ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- insert default price
            INSERT INTO catalog_product_entity_decimal (entity_type_id, entity_id, attribute_id, store_id, value)
            SELECT @entity_type_id, @product_id, @priceAttributeId, 0, tmd.field_value
			  FROM to_magento_datas tmd
             WHERE tmd.record_id = new.record_id
               AND tmd.field_name = 'Vejl_DKK'
            ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
               
			-- insert group prices
            INSERT INTO catalog_product_entity_group_price 
						(entity_id, 
                         all_groups, 
                         customer_group_id, 
                         value, 
                         website_id)
			SELECT @product_id, 
					0, 
                    cg.customer_group_id,
                    tmd.field_value,
                    hpw.website_id
			  FROM to_magento_datas tmd,
                   hd_pricegroup_website hpw,
                   customer_group cg
             WHERE tmd.record_id = new.record_id
               AND tmd.field_name = hpw.pricegroup
               AND cg.customer_group_code = tmd.field_name
               AND hpw.special = 1
            ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- call reindex
            CALL mmc_reindexProductPrice(@product_id);
            
            SET NEW.message = 'END PRICE IMPORT';
        END IF;
        -- -------------------- PRICE PART END -------------------------- --
        -- -------------------------------------------------------------- --
        
        -- -------------------------------------------------------------- --
        -- ----------------- CUSTOMER PART START ------------------------ --
        IF new.type = 5 THEN
			SET @customerEmail = NEW.identifier;
            
            SET @action = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'action' );
			SET @websiteId = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'website_id' );
			
            SET @entity_type_id = (SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code = 'customer');
            
            -- check if customer email is set
            IF @customerEmail = '' THEN
				SET NEW.message = 'Customer email not set';
                SET NEW.status = 3;
				LEAVE outer_block;
			END IF;
            
            -- get customer id
            SET @customer_id = (SELECT entity_id FROM customer_entity WHERE email = @customerEmail AND website_id = @websiteId);
            
            IF !@customer_id OR @customer_id IS NULL OR @customer_id = '' THEN
				INSERT INTO customer_entity (`website_id`, `email`) VALUES (@websiteId, @customerEmail);
                
                SET @customer_id = LAST_INSERT_ID();
            END IF;
            
            -- update customer attributes
            -- varchar
            INSERT IGNORE INTO customer_entity_varchar (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    @customer_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'varchar'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- int
            INSERT IGNORE INTO customer_entity_int (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    @customer_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'int'
               AND field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- decimal
            INSERT IGNORE INTO customer_entity_decimal (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    @customer_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'decimal'
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- text
            INSERT IGNORE INTO customer_entity_text (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    @customer_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'text'
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                              
            -- datetime
            INSERT IGNORE INTO customer_entity_datetime (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id as entity_type_id, 
					eav.attribute_id, 
                    @customer_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = IF(INSTR(td.field_name,'|'), SUBSTRING_INDEX(td.field_name,'|', 1), td.field_name)
               AND eav.entity_type_id = @entity_type_id
               AND eav.backend_type = 'datetime'
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- ---------------- --   
            -- CUSTOMER ADDRESS --
            
            -- BILLING ADDRESS
            SET @customer_addr_bll_id = checkCustomerAddress(NEW.record_id, 'addr_bll_');
            
            SET @entity_type_id_address = (SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code = 'customer_address');            
            
            IF !@customer_addr_bll_id OR @customer_addr_bll_id IS NULL OR @customer_addr_bll_id = '' THEN
				INSERT INTO customer_address_entity 
					(`entity_type_id`, 
                    `attribute_set_id`,
                    `increment_id`,
                    `parent_id`,
                    `is_active`) 
				VALUES (@entity_type_id_address, 
						0,
                        NULL,
                        @customer_id,
                        1);
                
                SET @customer_addr_bll_id = LAST_INSERT_ID();
                
            END IF;
            
		
			INSERT INTO customer_entity_int (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
			SELECT @entity_type_id as entity_type_id,
				   eav.attribute_id,
				   @customer_id,
				   @customer_addr_dlv_id
			  FROM eav_attribute eav
			 WHERE eav.entity_type_id = @entity_type_id
			   AND eav.attribute_code = 'default_billing'
			   ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- update customer address attributes
            -- varchar
            INSERT IGNORE INTO customer_address_entity_varchar (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_bll_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_bll_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'varchar'
               AND INSTR(td.field_name, 'addr_bll') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- int
            INSERT IGNORE INTO customer_address_entity_int (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_bll_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_bll_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'int'
               AND INSTR(td.field_name, 'addr_bll') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- decimal
            INSERT IGNORE INTO customer_address_entity_decimal (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_bll_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_bll_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'decimal'
               AND INSTR(td.field_name, 'addr_bll') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- text
            INSERT IGNORE INTO customer_address_entity_text (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_bll_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_bll_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'text'
               AND INSTR(td.field_name, 'addr_bll') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
               
            -- datetime
            INSERT IGNORE INTO customer_address_entity_datetime (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_bll_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_bll_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'datetime'
               AND INSTR(td.field_name, 'addr_bll') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            
            -- ------ DELIVERY ADDRESS --------
            SET @customer_addr_dlv_id = checkCustomerAddress(NEW.record_id, 'addr_dlv_');
            
            IF !@customer_addr_dlv_id OR @customer_addr_dlv_id IS NULL OR @customer_addr_dlv_id = '' THEN
				INSERT INTO customer_address_entity 
					(`entity_type_id`, 
                    `attribute_set_id`,
                    `increment_id`,
                    `parent_id`,
                    `is_active`) 
				VALUES (@entity_type_id, 
						0,
                        NULL,
                        @customer_id,
                        1);
                
                SET @customer_addr_dlv_id = LAST_INSERT_ID();
            
            END IF;
            
            INSERT INTO customer_entity_int (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
			SELECT @entity_type_id as entity_type_id,
				   eav.attribute_id,
				   @customer_id,
				   @customer_addr_dlv_id
			  FROM eav_attribute eav
			 WHERE eav.entity_type_id = @entity_type_id
			   AND eav.attribute_code = 'default_shipping'
			   ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- update customer address attributes
            -- varchar
            INSERT IGNORE INTO customer_address_entity_varchar (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_dlv_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_dlv_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'varchar'
               AND INSTR(td.field_name, 'addr_dlv') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- int
            INSERT IGNORE INTO customer_address_entity_int (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_dlv_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_dlv_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'int'
               AND INSTR(td.field_name, 'addr_dlv') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- decimal
            INSERT IGNORE INTO customer_address_entity_decimal (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_dlv_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_dlv_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'decimal'
               AND INSTR(td.field_name, 'addr_dlv') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
            -- text
            INSERT IGNORE INTO customer_address_entity_text (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_dlv_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_dlv_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'text'
               AND INSTR(td.field_name, 'addr_dlv') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
               
            -- datetime
            INSERT IGNORE INTO customer_address_entity_datetime (`entity_type_id`, `attribute_id`, `entity_id`, `value`)
            SELECT @entity_type_id_address as entity_type_id, 
					eav.attribute_id, 
                    @customer_addr_dlv_id as `entity_id`,
                    field_value as `value`
              FROM to_magento_datas td,
                   eav_attribute eav
             WHERE td.record_id = NEW.record_id
               AND eav.attribute_code = REPLACE(td.field_name, 'addr_dlv_','')
               AND eav.entity_type_id = @entity_type_id_address
               AND eav.backend_type = 'datetime'
               AND INSTR(td.field_name, 'addr_dlv') = 1
               AND td.field_value != ''
               ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
            
        END IF;
        -- ----------------- CUSTOMER PART END -------------------------- --
        -- -------------------------------------------------------------- --
	END IF;
END outer_block
//
delimiter ;