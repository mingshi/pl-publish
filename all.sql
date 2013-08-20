create table server (
    `id` int not null auto_increment,
    `name` varchar(50) not null default '' comment '主机名称',
    `server_address` varchar(255) NOT NULL DEFAULT '' comment '主机地址',
    `repo_address` varchar(255) NOT NULL DEFAULT '' comment '仓库地址',
    PRIMARY KEY (`id`)
) engine=innodb default charset utf8;

create table user (
    `id` int not null auto_increment,
    `uid` int not null default '0' comment '用户id',
    `username` varchar(50) not null default '' comment '用户名',
    `realname` varchar(50) NOT NULL DEFAULT '',
    `login_time` timestamp NULL DEFAULT NULL,
    `login_ip` varchar(50) DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uid` (`uid`)
) engine=innodb default charset utf8;
