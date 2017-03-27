DROP TABLE IF EXISTS `magento_field_matches`;

CREATE TABLE `magento_field_matches` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `type` int(11) DEFAULT NULL,
  `cloud_biz_field_name` varchar(255) DEFAULT NULL,
  `magento_field_name` varchar(255) DEFAULT NULL,
  `magento_store_id` smallint(5) unsigned,
  `magento_attribute_id` smallint(5) unsigned,
  `created` datetime DEFAULT NULL,
  `modified` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=FEDERATED CONNECTION='magento_s' DEFAULT CHARSET=latin1;