package Pb::IPUB::Mypub;
use Mojo::Base 'MY::Controller';
use Mojo::Util qw/encode decode/;
use MY::Utils;
use Mojo::JSON;
use JSON::XS;
use Data::Dumper;
use autodie;
use Try::Tiny;
use POSIX qw(strftime);
use Time::Local;
use Date::Parse;

sub index {
    my $self = shift;
    my $uid = $self->current_user->{info}{id};
    my $where = {};
    $where->{-bool} = "find_in_set('$uid', who)";
    $where->{status} = $M::User::SERVER_STATUS_OK;
    my $attrs = {
        'order_by'  =>  '-id',  
    };
   
    $self->set_list_data('server', $where, $attrs);

    my $serverStatus = {
        status_ok => $M::User::SERVER_STATUS_OK,
        status_del => $M::User::SERVER_STATUS_DELETE,
    };    
    my %data = (
        serverStatus => $serverStatus,
    );
    $self->render('mypub_list', %data);
    return;
}

sub getUser {
    my $self = shift;
    my %params = $self->param_request({
        uids => 'STRING', 
    });

    my $where = {};

    $where->{uid} = [
        split(',' ,$params{uids})
    ];
   
    my $attrs = {};
    $self->set_list_data('user', $where, $attrs);

    my $users = $self->stash('list_data');
    my $usersStr = "";
    for my $user (@$users) {
        $usersStr .= $user->{realname}.",";
    }

    $usersStr =~ s/^,|,$//g;

    $self->render(text => $usersStr);
    return;
}

sub rollback {
    my $self = shift;
    my %params = $self->param_request({
        id  =>  'UINT',
    });

    my $uid = $self->current_user->{info}{id};
    my $server = M('server')->find({ id =>  $params{id} });

    if (hard_matches($uid, $server->{data}->{who}) != 1) {
        my $msg = "你对该主机没有权限";
        $self->fail($msg);
        return $self->redirect_to('/mypub');
    }

    if (!$server) {
        my $msg = '主机不存在';
        $self->fail($msg);
        return $self->redirect_to('/mypub');
    } else {
        my $serverStatus = {
            status_ok => $M::User::SERVER_STATUS_OK,
            status_del => $M::User::SERVER_STATUS_DELETE,
        };
        
        my @serverList = split(',', $server->{data}->{server_address});
        
        my $serversCount = @serverList;
        my $divWidth = int(100 / $serversCount); 

        my %data = (
            server  =>  $server->{data},
            serverList  =>  \@serverList,
            serverStatus => $serverStatus,
            divWidth    =>  $divWidth,
            serversCount    =>  $serversCount,
        );

        $self->render('rollback', %data);
        return;

    }
}

sub pull {
    my $self = shift;
    my %params = $self->param_request({
        id  =>  'UINT',
    });

    my $uid = $self->current_user->{info}{id};
    my $server = M('server')->find({ id => $params{id} });
    
    if (!$server) {
        my $msg = '主机不存在';
        $self->fail($msg);
        return $self->redirect_to('/mypub');
    } else {
        if (hard_matches($uid, $server->{data}->{who}) != 1) {
            my $msg = "你对该主机没有权限";
            $self->fail($msg);
            return $self->redirect_to('/mypub');
        }

        my $serverStatus = {
            status_ok => $M::User::SERVER_STATUS_OK,
            status_del => $M::User::SERVER_STATUS_DELETE,
        };
        my @serverList = split(',', $server->{data}->{server_address});
        my %data = (
            server  =>  $server->{data},
            serverList  =>  \@serverList,
            serverStatus => $serverStatus,
        );

        $self->render('pull', %data);
        return;
    }
}

sub do_rollback {
    my $self = shift;
    if ($self->req->method eq "POST") {
        my %params = $self->param_request({
            id  =>  'UINT',
            commit  =>  'STRING',
            is_run_script   =>  'UINT',
        });

        my $rockServers = join(",", $self->param('server_address'));
        unless ($params{id} && $rockServers) {
            return $self->fail('请完整填写参数');
        }

        my $tmpServer = M('server')->find({ id => $params{id} });

        my $uid = $self->current_user->{info}{id};
        if (hard_matches($uid, $tmpServer->{data}->{who}) != 1) {
            my $msg = '你对该主机没有权限';
            return $self->fail($msg);
        }
        
        if (!$tmpServer) {
            my $msg = '主机不存在';
            $self->fail($msg);
            return $self->redirect_to('/mypub');
        } else {
            my $dir = $self->app->home->rel_dir('./script');
            my $now = time();
            my $file = $dir . "/mussh/hosts/rock-" . $params{id} . "-" . $now;
            
            unless (open (MYFILE, ">:utf8", $file)) {
                my $msg = '无法创建临时文件';
                $self->fail($msg);
                return;
            }

            print MYFILE join("\n", $self->param('server_address'));
            close MYFILE;
           
            my $res = "";
            if ($params{commit}) {
                $params{commit} =~ s/^\s+|\s+$//g;
                if ($params{commit} =~ /^([0-9a-z]+)$/) {
                    $res = `$dir/rock.sh ${dir} $tmpServer->{data}->{server_root} $file $params{commit}`;
                } else {
                    if (-f $file) {
                        unlink($file);
                    }
                    $self->fail("你想干嘛？你看看你提交的commit是啥玩意儿？");
                    return;
                }
            } else {
                $res = `$dir/rock.sh ${dir} $tmpServer->{data}->{server_root} $file`;
            }
            
            my $qqRes = $res;

            $res =~ s/\r?\n/\<br \/\>/g;
            M('log')->insert({
                uid => $uid,
                server_id   =>  $params{id},
                type    =>  '2',
                res  =>  "$res",
                time    =>  \'current_timestamp'
            });
            
            my $secRes = "回退失败";
            if ($res ~~ /HEAD is now at/) {
                $tmpServer->{data}->{script} =~ s/^\s+|\s+$//g;
                $secRes = "回退成功";
                if ($tmpServer->{data}->{script} and $params{is_run_script}) {
                    my $scriptRes = `$dir/script.sh ${dir} $file "$tmpServer->{data}->{script}"`;
                    my @lines = split /\n\r?/, $scriptRes;
                    if ($lines[-1] eq 0) {
                        $secRes .= "\n脚本执行成功";
                        $secRes =~ s/\r?\n/\<br \/\>/g;
                        $self->info($secRes);
                    } else {
                        $secRes .= "\n脚本执行失败";
                        $secRes =~ s/\r?\n/\<br \/\>/g;
                        $self->fail($secRes);
                    }
                } else {
                    $self->info($secRes);
                }
            } else {
                $self->fail($secRes);
            }

            if (-f $file) {
                unlink($file);
            }
            
            my $qqInfo = $self->current_user->{info}{realname} ." 回退了 " . $tmpServer->{data}->{name} . "   结果为:\n" . $qqRes;
            M::User::send_qq_info($self, $tmpServer->{data}{attention}, $qqInfo);

            return;
        }
    }
}

sub do_pull {
    my $self = shift;
    if ($self->req->method eq "POST") {
        my %params = $self->param_request({
            id  => 'UINT',
            is_run_script   =>  'UINT',
        });

        my $pullServers = join(",", $self->param('server_address'));
        unless ($params{id} && $pullServers) {
            return $self->fail('请完整填写参数');
        }

        my $tmpServer = M('server')->find({ id => $params{id} });

        if (!$tmpServer) {
            my $msg = '主机不存在';
            $self->fail($msg);
            return $self->redirect_to('/mypub');
        } else {
            my $uid = $self->current_user->{info}{id};
            if (hard_matches($uid, $tmpServer->{data}->{who}) != 1) {
                my $msg = '你对该主机没有权限';
                return $self->fail($msg);
            }
      
            my $dir = $self->app->home->rel_dir('./script');
            
            my $now = time();
            my $file = $dir . "/mussh/hosts/pull-" . $params{id} . "-" . $now;
           
            unless (open (MYFILE, ">:utf8", $file)) {
                my $msg = '无法创建临时文件';
                $self->fail($msg);
                return;
            }

            print MYFILE join("\n", $self->param('server_address'));
            close MYFILE;

            my $res = `$dir/pull.sh $tmpServer->{data}->{server_root} $file $tmpServer->{data}->{repo_address} ${dir}`;
            my $qqRes = $res;
            $res =~ s/\r?\n/\<br \/\>/g;
            M('log')->insert({
                uid => $uid,
                server_id   =>  $params{id},
                type    =>  '1',
                res  =>  "$res",
                time    =>  \'current_timestamp'
            });
           
            my $secRes = "上线失败";
            if ($res ~~ /Already up-to-date/ or $res ~~ /Fast-forward/) {
                $tmpServer->{data}->{script} =~ s/^\s+|\s+$//g;
                $secRes = "上线成功";
                if ($tmpServer->{data}->{script} and $params{is_run_script}) {
                    my $scriptRes = `$dir/script.sh ${dir} $file "$tmpServer->{data}->{script}"`;
                    my @lines = split /\n\r?/, $scriptRes;
                    if ($lines[-1] eq 0) {
                        $secRes .= "\n脚本执行成功";
                        $secRes =~ s/\r?\n/\<br \/\>/g; 
                        $self->info($secRes);
                    } else {
                        $secRes .= "\n脚本执行失败";
                        $secRes =~ s/\r?\n/\<br \/\>/g;
                        $self->fail($secRes);
                    }
                } else {
                    $self->info($secRes);
                }
            } else {
                $self->info($secRes);
            }
            
            if (-f $file) {
                unlink($file);
            }
            
            my $qqInfo = $self->current_user->{info}{realname} ." 上线了 " . $tmpServer->{data}->{name} . "   结果为:\n" . $qqRes;
            M::User::send_qq_info($self, $tmpServer->{data}{attention}, $qqInfo);
            return;

        }
    }
}

sub detail {
    my $self = shift;
    my %params = $self->param_request({
        id  =>  'UINT',
        page => 'UINT',
        pagesize => 'UINT',
    });
    
    my $page = $params{page} || 1;
    my $pagesize = $params{pagesize} || 15;

    my $where = {};
    $where->{'me.server_id'} = $params{id};
    my $attrs = {
        'order_by' => '-me.id',
        'page'  =>  $page,
        'rows_per_page' =>  $pagesize,
        'left_join' =>  ['user', { 'me.uid' => 'user.uid' }],
        'select'    =>  'me.*, user.realname',
    };
    
    my $server = M('server')->find({ id => $params{id} });
    if (!$server) {
        my $msg = '主机不存在';
        $self->fail($msg);
        return;
    }

    my $uid = $self->current_user->{info}{id};

    if (hard_matches($uid, $server->{data}->{who}) != 1) {
        my $msg = '你对该主机没有权限';
        $self->fail($msg);
        return;
    }

    $self->set_list_data('log', $where, $attrs);

    $self->render('mypubdetail');

}

sub serverInfo {
    my $self = shift;
    my %params = $self->param_request({
        host    =>  'STRING',
        id      =>  'UINT',
    });
   
    my $res;
    my $server = M('server')->find({ id => $params{id} });
    if (!$server) {
        $res = '找不到该主机';
    } else {
        try {
            my $serverDir = $server->{data}->{server_root};
            $res = `ssh -o StrictHostKeyChecking=no $params{host} 'cd $serverDir;git log|head -60'`;
        } catch {
            $res = '远程获取状态失败';
        }

    }

    $res = decode('UTF-8', $res);
    $self->render(text  =>  $res);
}

sub hard_matches {
    my $f = "," . shift . ",";
    my $s = "," . shift . ",";
    my $w = grep(/$f/, $s);
    return $w;
}

sub punchCard {
    my $self = shift;
    my $uid = $self->current_user->{info}{id};
    my %params = $self->param_request({
        searchStartDate =>  'STRING',
        searchEndDate   =>  'STRING',
    });

    $params{searchStartDate} //= strftime "%Y-%m-%d", localtime(time() - 86400 * 7);
    $params{searchEndDate} //= strftime("%Y-%m-%d", localtime());

    $params{searchStartDate} =~ s/\-//g;
    $params{searchEndDate} =~ s/\-//g;

    my @rows = M('log', 'ipublish')->select({
        -and   => [
            'FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%Y%m%d")'    =>  { '>=' => "$params{searchStartDate}" },
            'FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%Y%m%d")'    =>  { '<=' => "$params{searchEndDate}" },
            'me.type'    =>  1,
            'me.uid'     =>  $uid,
        ],
    }, {
        'select' => 'count(*) as total, FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%Y%m%d") as t, FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%H") as h',
        'group_by' => 't,h',
    })->all; 
   

    my $tmpRes = {};
    for my $item (@rows) {
        $item->{data}->{h} =~ s/^0//g;
        $tmpRes->{$item->{data}->{t}}->{$item->{data}->{h}} = $item->{data}->{total};
    }
   
    my @dateStep;
    my @allData;
    
    for (my $t = $params{searchStartDate}; $t le $params{searchEndDate}; $t = strftime "%Y%m%d", localtime(str2time($t) + 86400)) {
        push(@dateStep, $t);
        for (my $h = 0; $h <= 23; $h++) {
            if ($tmpRes->{$t}->{$h} and $tmpRes->{$t}->{$h} ne 0) {
                push(@allData, [$h,$t,$tmpRes->{$t}->{$h}]);
            } else {
                push(@allData, [$h,$t,0]); 
            }
        }
    }

    my %res = (
        dateStep    =>  \@dateStep,
        allData     =>  \@allData,
    );

    my $result = encode_json(\%res);
    $result =~ s/"//g;
    $result =~ s/allData/"allData"/g;
    $result =~ s/dateStep/"dateStep"/g;
    $self->render(text => $result);
    return;
}


sub my_charts {
    my $self = shift;
    my $uid = $self->current_user->{info}{id};
    
    my %params = $self->param_request({
        searchStartDate =>  'STRING', 
        searchEndDate   =>  'STRING',
    });

    $params{searchStartDate} //= strftime "%Y-%m-%d", localtime(time() - 86400 * 7);
    $params{searchEndDate} //= strftime("%Y-%m-%d", localtime());

    # get the pull count between the search time
    my @rows = M('log', 'ipublish')->select({
        -and   => [
            'FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%Y-%m-%d")'    =>  { '>=' => "$params{searchStartDate}" },
            'FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%Y-%m-%d")'    =>  { '<=' => "$params{searchEndDate}" },
            'me.type'    =>  1,
            'me.uid'     =>  $uid,
        ], 
    }, {
        'select' => 'count(*) as total, FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%Y-%m-%d") as t',
        'group_by' => 't',
    })->all;  
   
    my @rows1 = M('log', 'ipublish')->select({
        -and   => [
            'FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%Y-%m-%d")'    =>  { '>=' => "$params{searchStartDate}" },
            'FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%Y-%m-%d")'    =>  { '<=' => "$params{searchEndDate}" },
            'me.type'    =>  2,
            'me.uid'     =>  $uid,
        ],
    }, {
        'select' => 'count(*) as total, FROM_UNIXTIME(UNIX_TIMESTAMP(me.time), "%Y-%m-%d") as t',
        'group_by' => 't',
    })->all;

    my $resPull = {};
    my $resRoll = {};
    
    for my $item (@rows) {
        $resPull->{$item->{data}->{t}} = $item->{data}->{total};
    }

    for my $item1 (@rows1) {
        $resRoll->{$item1->{data}->{t}} = $item1->{data}->{total};
    }

    for (my $t = $params{searchStartDate}; $t le $params{searchEndDate}; $t = strftime "%Y-%m-%d", localtime(str2time($t) + 86400)) {
        $resPull->{$t} //= 0;
        $resRoll->{$t} //= 0;
    }

    my @keyPull = sort(keys %{$resPull});
    my @valuePull;
    my @valueRoll;

    my $keyStr = "";
    my $valuePullStr = "";
    my $valueRollStr = "";
    for my $date (@keyPull) {
        $keyStr .= "'".$date."',";
        push(@valuePull, $resPull->{$date});
        push(@valueRoll, $resRoll->{$date});
    }
    
    $keyStr = encode_json(\@keyPull);
    $valuePullStr = encode_json(\@valuePull);
    $valueRollStr = encode_json(\@valueRoll);

    $keyStr =~ s/"/'/g;
    $valuePullStr =~ s/"//g;
    $valueRollStr =~ s/"//g;
    my %data = (
        startDate   =>  $params{searchStartDate},
        endDate     =>  $params{searchEndDate},
        keyStr      =>  $keyStr,
        valuePullStr => $valuePullStr,
        valueRollStr => $valueRollStr,
    );


    $self->render('my_charts', %data);
    return;
}

1;
