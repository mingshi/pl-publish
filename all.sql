create table server (
    `id` int not null auto_increment,
    `name` varchar(50) not null default '' comment '主机名称',
    `server_address` varchar(255) NOT NULL DEFAULT '' comment '主机地址',
    `repo_address` varchar(255) NOT NULL DEFAULT '' comment '仓库地址',
    PRIMARY KEY (`id`)
) engine=innodb default charset utf8;
