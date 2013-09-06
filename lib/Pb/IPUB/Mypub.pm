package Pb::IPUB::Mypub;
use Mojo::Base 'MY::Controller';
use Mojo::Util qw/encode decode/;
use MY::Utils;
use Mojo::JSON;
use JSON::XS;
use Data::Dumper;
use autodie;
use Try::Tiny;

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
            name    =>  'STRING',
            repo_address    =>  'STRING',
            server_root =>  'STRING',
            commit  =>  'STRING',
            script  =>  'STRING',
            is_run_script   =>  'UINT',
        });

        my $rockServers = join(",", $self->param('server_address'));
        unless ($params{id} && $params{repo_address} && $params{server_root} && $rockServers) {
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
                $res = `$dir/rock.sh ${dir} $params{server_root} $file $params{commit}`;
            } else {
                $res = `$dir/rock.sh ${dir} $params{server_root} $file`;
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
                $params{script} =~ s/^\s+|\s+$//g;
                $secRes = "回退成功";
                if ($params{script} and $params{is_run_script}) {
                    my $scriptRes = `$dir/script.sh ${dir} $file "$params{script}"`;
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
            name => 'STRING',
            repo_address    =>  'STRING',
            server_root =>  'STRING',
            script  =>  'STRING',
            is_run_script   =>  'UINT',
        });

        my $pullServers = join(",", $self->param('server_address'));
        unless ($params{id} && $params{repo_address} && $params{server_root} && $pullServers) {
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

            my $res = `$dir/pull.sh $params{server_root} $file $params{repo_address} ${dir}`;
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
                $params{script} =~ s/^\s+|\s+$//g;
                $secRes = "上线成功";
                if ($params{script} and $params{is_run_script}) {
                    my $scriptRes = `$dir/script.sh ${dir} $file "$params{script}"`;
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


1;
