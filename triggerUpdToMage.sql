delimiter //
DROP FUNCTION IF EXISTS getMagentoField //
CREATE FUNCTION getMagentoField ( bizField VARCHAR(255) ) RETURNS VARCHAR(255)
BEGIN
	CASE bizField
		WHEN 'cat_name_uk' THEN RETURN 'name';
        WHEN 'is_active_uk' THEN RETURN 'is_active';
        ELSE RETURN '';
	END CASE;
END //

DROP FUNCTION IF EXISTS getMagentoFieldStore //
CREATE FUNCTION getMagentoFieldStore ( bizField VARCHAR(255) ) RETURNS VARCHAR(255)
BEGIN
	RETURN 0;

	CASE bizField
		WHEN 'cat_name_uk' THEN RETURN 'uk';
        WHEN 'is_active_uk' THEN RETURN 'uk';
        ELSE RETURN 0;
	END CASE;
END //


DROP TRIGGER IF EXISTS triggerUpdToMage //
CREATE TRIGGER triggerUpdToMage BEFORE UPDATE ON to_magento_records
FOR EACH ROW
outer_block:BEGIN
	DECLARE done INT DEFAULT FALSE;
	DECLARE fieldName VARCHAR(255);
    DECLARE fieldValue TEXT;
	DECLARE c_categoryData CURSOR FOR SELECT field_name, field_value FROM to_magento_datas WHERE record_id = NEW.record_id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

	IF NEW.status = 0 THEN
		SET NEW.status = 1; 
		
		-- category
		IF new.type = 1 THEN
			SET NEW.message = 'update category';
			
			-- get category id
			SET @categoryid = NEW.identifier;
			
			-- get action
			SET @action = (SELECT IFNULL(field_value,'') FROM to_magento_datas WHERE record_id = NEW.record_id AND field_name = 'action' );
			
			IF @action = '' THEN
				SET NEW.message = 'Action field not set';
				LEAVE outer_block;
			END IF;
			
			-- insert into catalog_category_entity
			SET @entity_id = IF(@categoryid=0,NULL,@categoryid);
			SET @entity_type_id = 3;
			SET @attribute_set_id = 3;
			SET @path = CONCAT('1/2/', @categoryid);
			SET @parent_id = 2;
			
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
                SET @magentoFieldStore = getMagentoFieldStore(fielName);
                
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
			
			CLOSE c_categoryData;			
			
		END IF;
		
		IF new.type = 2 THEN
			SET NEW.message = 'update product';
		END IF;
		
	END IF;
END outer_block
//
delimiter ;