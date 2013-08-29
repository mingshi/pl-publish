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

alter table server add server_root varchar(255) not null default '/tmp/' comment '主机目录';
alter table server add status tinyint(1) not null default '1' comment '主机状态，1:正常，0:删除';
alter table server add varchar(255) NOT NULL DEFAULT '0' COMMENT '分配用户';

create table log (
    `id` int not null auto_increment,
    `uid` int not null default '0' comment '用户id',
    `server_id` int not null default '0' comment '主机id',
    `type` tinyint(1) not null default '0' comment '操作类型1:上线,2:回退',
    `res` text,
    `time` timestamp NULL DEFAULT NULL,
    PRIMARY KEY (`id`)
) engine=innodb default charset utf8;

alter table server add attention varchar(255) NOT NULL DEFAULT '0' COMMENT '关注用户';
