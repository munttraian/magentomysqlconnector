DROP TABLE `to_magento_records`;
CREATE TABLE `to_magento_records` (
  `id` bigint(32) NOT NULL AUTO_INCREMENT,
  `record_id` bigint(32) DEFAULT NULL,
  `identifier` varchar(255) DEFAULT NULL,
  `type` int(11) DEFAULT NULL,
  `message` varchar(255) DEFAULT NULL,
  `status` tinyint(4) DEFAULT '0',
  `created` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8; -- COLLATE=utf8_general_ci;

DROP TABLE `to_magento_datas`;
CREATE TABLE `to_magento_datas` (
  `id` bigint(32) NOT NULL AUTO_INCREMENT,
  `record_id` bigint(32) DEFAULT NULL,
  `field_name` varchar(255) DEFAULT NULL,
  `field_value` text,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8; -- COLLATE=utf8_general_ci;

