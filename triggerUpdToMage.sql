delimiter //
-- get magento attribute code based on bizcloud fieldname
DROP FUNCTION IF EXISTS getMagentoField //
CREATE FUNCTION getMagentoField ( bizField VARCHAR(255) ) RETURNS VARCHAR(255)
BEGIN
	-- SET @fieldMagento = (SELECT magento_field_name FROM magento_field_matches WHERE cloud_biz_field_name = bizField);
    SET @fieldMagento = (SELECT IF(INSTR(magento_field_name,'|'), SUBSTRING_INDEX(magento_field_name,'|', 1), magento_field_name) FROM magento_field_matches WHERE cloud_biz_field_name = bizField);
    
    RETURN @fieldMagento;
END //

-- get magento store id
DROP FUNCTION IF EXISTS getMagentoFieldStore //
CREATE FUNCTION getMagentoFieldStore ( bizField VARCHAR(255) ) RETURNS VARCHAR(255)
BEGIN
	-- SET @fieldMagentoStore = (SELECT IF(INSTR(magentofield_id_magento,'|'), SUBSTRING_INDEX(magentofield_id_magento,'|',-1), 0) FROM magento_field_matches WHERE field_id_biz_cloud = bizField);
    SET @fieldMagentoStore = (SELECT magento_store_id FROM magento_field_matches WHERE cloud_biz_field_name = bizField);
    
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
CREATE FUNCTION getConfigurableAttributes( p_attributeSetId VARCHAR(255) ) RETURNS VARCHAR(255)
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
CREATE FUNCTION countOccurence ( p_text TEXT, p_needle VARCHAR(255) ) RETURNS int
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
CREATE FUNCTION getSetElementByIndex ( p_settext TEXT, p_ind INT) RETURNS varchar(255)
BEGIN
	DECLARE v_element VARCHAR(255);
    
    SELECT substring_index(substring_index(p_settext, ',', p_ind), ',', -1)
    INTO v_element;

	RETURN v_element;
END //

-- create stock line
DROP PROCEDURE IF EXISTS addStockLine //
CREATE PROCEDURE addStockLine( p_productId int, p_websiteIds TEXT)
BEGIN
	
    INSERT IGNORE INTO cataloginventory_stock_item (product_id, stock_id, qty, is_in_stock)
    VALUES (p_productId, 1, 0, 0);
    
    INSERT IGNORE INTO cataloginventory_stock_status (`product_id`, `website_id`, `stock_id`, `qty`, `stock_status`)
    SELECT p_productId, w.website_id, 1, 0, 0
      FROM core_website w
     WHERE FIND_IN_SET(w.website_id, p_websiteIds); 
    
END //

DROP TRIGGER IF EXISTS triggerUpdToMage //
CREATE TRIGGER triggerUpdToMage BEFORE UPDATE ON to_magento_records
FOR EACH ROW
outer_block:BEGIN
	DECLARE done INT DEFAULT FALSE;
	DECLARE fieldName VARCHAR(255);
    DECLARE fieldValue TEXT;
    DECLARE indImage INT DEFAULT 0;
    DECLARE imageName VARCHAR(255);
    
	DECLARE c_categoryData CURSOR FOR SELECT field_name, field_value FROM to_magento_datas WHERE record_id = NEW.record_id;
    DECLARE c_productData CURSOR FOR SELECT field_name, field_value FROM to_magento_datas WHERE record_id = NEW.record_id;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

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
			SET @entity_type_id = 3;
			SET @attribute_set_id = 3;
			SET @path = CONCAT('1/2/', @categoryid);
			SET @parent_id = 2;
			
            -- treat delete action
            IF @action = 2 THEN
				SET NEW.message = 'Delete category';
				DELETE FROM catalog_category_entity WHERE entity_id = @entity_id;
                LEAVE outer_block;
            END IF;
            
            -- treat create/update action
			INSERT INTO catalog_category_entity (`entity_id`,`entity_type_id`, `attribute_set_id`, `path`, `parent_id`)
			VALUES (@entity_id, @entity_type_id, @attribute_set_id, @path, @parent_id)
			ON DUPLICATE KEY UPDATE `path` = VALUES(`path`);
			
            -- if new category id update category id
			IF @categoryid = 0 THEN 
				SET @categoryid = LAST_INSERT_ID(); 
                SET NEW.identifier = @categoryid;
			END IF;
			
			-- get category data
			OPEN c_categoryData;
			
            -- foreach each field line
			read_loop: LOOP
				FETCH c_categoryData INTO fieldName, fieldValue;
				
				IF done THEN
					LEAVE read_loop;
				END IF;	
                
                SET NEW.message = CONCAT(fieldName, ' ', fieldValue);
                
                -- get attribute id
				SET @attributeId = (SELECT IFNULL(attribute_id,0) FROM eav_attribute WHERE attribute_code = getMagentoField(fieldName) AND entity_type_id = 3);
				SET @backendType = (SELECT backend_type FROM eav_attribute WHERE attribute_code = getMagentoField(fieldName) AND entity_type_id = 3);
				SET @attributeTable = CONCAT('catalog_category_entity_',@backendType);
                SET @magentoFieldStore = getMagentoFieldStore(fieldName);
                
                -- CALL logMessage( CONCAT('Attribute id ', @attributeId, ' Backend Type ', @backendType, ' Attribute table ', @attributeTable, ' Magento store id', @magentoFieldStore) );
                CALL logMessage(CONCAT('Treat ', getMagentoField(fieldName)));
                CALL logMessage(@attributeId);
                -- CALL logMessage(@backendType);
                -- CALL logMessage(@attributeTable);
                
                -- if not an attribute then go next field
                IF @attributeId = 0 THEN
					ITERATE read_loop;
                END IF;
                
                SET NEW.message = CONCAT('update ',fieldName);
                
                CASE @backendType
					WHEN 'varchar' THEN
						BEGIN
							INSERT INTO catalog_category_entity_varchar (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @categoryid, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;
                    WHEN 'int' THEN
						BEGIN
							INSERT INTO catalog_category_entity_int (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @categoryid, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;
                    WHEN 'decimal' THEN
						BEGIN
							INSERT INTO catalog_category_entity_decimal (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @categoryid, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;
                    WHEN 'datetime' THEN
						BEGIN
							INSERT INTO catalog_category_entity_datetime (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @categoryid, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;
                    WHEN 'text' THEN
						BEGIN
							INSERT INTO catalog_category_entity_text (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @categoryid, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;    
					ELSE
						BEGIN
                        END;
                END CASE;    
                
			END LOOP;
            
            -- update path based on parent id
            SET @parent_id = (SELECT parent_id FROM catalog_product_entity WHERE entity_id = @category_id);
            SET @parent_path = (SELECT path FROM catalog_product_entity WHERE entity_id = @parent_id);
            
            UPDATE catalog_category_entity
               SET path = CONCAT(@parent_path,'/',@category_id)
             WHERE entity_id = @category_id;  
			
			CLOSE c_categoryData;			
			
		END IF;
		
        
        -- -------------------------------------------------------------- --
        -- -------------------- PRODUCT PART ---------------------------- --
		IF new.type = 2 THEN
			SET NEW.message = 'update product';
            
            SET @sku = NEW.identifier;
            
            -- get action
			SET @action = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'action' );
			SET @type_id = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'prod_type_id' );
			SET @product_id = (SELECT entity_id FROM catalog_product_entity WHERE sku = @sku);
			SET @productCategoryIds  = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'prod_category_ids' );
            SET @productWebsiteIds  = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'prod_website_ids' );
            
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
            IF @type_id = '' THEN
				SET @type_id = 'simple';
            END IF;
            
            -- get basic product data
			SET @entity_id = IF(@product_id=0,NULL,@product_id);
			SET @entity_type_id = 4;
			SET @attribute_set_id = 4;
			
            -- treat delete action
            IF @action = 2 THEN
				SET NEW.message = 'Delete product';
				DELETE FROM catalog_product_entity WHERE entity_id = @entity_id;
                LEAVE outer_block;
            END IF; 
            
            -- if new product update product id
			IF @product_id IS NULL THEN 
				-- treat create/update action
				INSERT INTO catalog_product_entity (`entity_id`,`entity_type_id`, `attribute_set_id`, `type_id`, `sku`, `has_options`, `required_options`, `created_at`, `updated_at`)
				VALUES (NULL, @entity_type_id, @attribute_set_id, @type_id, @sku, 0, 0, now(), now())
				ON DUPLICATE KEY UPDATE `updated_at` = VALUES(`updated_at`);
                
				SET @product_id = LAST_INSERT_ID(); 
                
                SET @entity_id = @product_id;
                -- SET NEW.identifier = @product_id;
			END IF;
            
            -- get product data
			OPEN c_productData;
            
            -- foreach each field line
			read_loop_prod: LOOP
				FETCH c_productData INTO fieldName, fieldValue;
				
				IF done THEN
					LEAVE read_loop_prod;
				END IF;
                
                -- get attribute id
				SET @attributeId = (SELECT IFNULL(attribute_id,0) FROM eav_attribute WHERE attribute_code = getMagentoField(fieldName) AND entity_type_id = 4);
				SET @backendType = (SELECT backend_type FROM eav_attribute WHERE attribute_code = getMagentoField(fieldName) AND entity_type_id = 4);
				SET @attributeTable = CONCAT('catalog_product_entity_',@backendType);
                SET @magentoFieldStore = getMagentoFieldStore(fieldName);
                
                -- if not an attribute then go next field
                IF @attributeId = 0 THEN
					ITERATE read_loop_prod;
                END IF;
                
				-- if media gallery, custom treat
                IF getMagentoField(fieldName) = 'media_gallery' THEN
                
					-- split image text
                    SET @v_image_count = countOccurence( fieldValue, ',' );
                    SET indImage = 0;
                    
                    image_loop: LOOP
						
                        SET indImage = indImage + 1;
                        
                        -- exit when all images are treated
                        IF indIMage > (@v_image_count + 1) THEN 
							LEAVE image_loop;
                        END IF;
                        
                        -- get image name
                        SET imageName = getSetElementByIndex( fieldValue, indImage );
                        
                        -- insert into media gallery
                        INSERT IGNORE INTO catalog_product_entity_media_gallery (attribute_id, entity_id, value)
                        VALUES (@attribute_id, @product_id, imageName);
                        
                        -- insert into media catalog_product_entity_media_gallery_value
                        INSERT INTO catalog_product_entity_media_gallery_value (value_id, store_id, `position`)
                        SELECT m.value_id, @magentoFieldStore,  indImage
						  FROM catalog_product_entity_media_gallery m
						 WHERE m.entity_id = @product_id
						   AND m.value = imageName
						   ON DUPLICATE KEY UPDATE `position` = indImage;
                        
                    END LOOP; -- image_loop
                    
                
					ITERATE read_loop_prod; -- continue with next attribute/datas
                END IF;
                
                SET NEW.message = CONCAT('update ',fieldName);
                
                CASE @backendType
					WHEN 'varchar' THEN
						BEGIN
							INSERT INTO catalog_product_entity_varchar (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @product_id, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;
                    WHEN 'int' THEN
						BEGIN
							INSERT INTO catalog_product_entity_int (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @product_id, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;
                    WHEN 'decimal' THEN
						BEGIN
							INSERT INTO catalog_product_entity_decimal (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @product_id, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;
                    WHEN 'datetime' THEN
						BEGIN
							INSERT INTO catalog_product_entity_datetime (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @product_id, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;
                    WHEN 'text' THEN
						BEGIN
							INSERT INTO catalog_product_entity_text (`entity_type_id`, `attribute_id`, `store_id`, `entity_id`, `value`)
							VALUES (@entity_type_id, @attributeId, @magentoFieldStore, @product_id, fieldValue)
							ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);
                        END;    
					ELSE
						BEGIN
                        END;
                END CASE;                
                
            END LOOP; -- end loop product datas
            
            -- add products to category
			INSERT IGNORE INTO catalog_category_product (category_id, product_id)
			SELECT c.entity_id, @product_id
			  FROM catalog_category_entity c
			 WHERE FIND_IN_SET(c.entity_id, @productCategoryIds); 
             
            -- add products to website
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
            
		END IF;
		
	END IF;
END outer_block
//
delimiter ;