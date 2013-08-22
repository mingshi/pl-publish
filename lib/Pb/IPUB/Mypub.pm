package Pb::IPUB::Mypub;
use Mojo::Base 'MY::Controller';
use Mojo::Util qw/encode/;
use MY::Utils;
use Mojo::JSON;
use JSON::XS;
use Data::Dumper;

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
        my %data = (
            server  =>  $server->{data},
            serverList  =>  \@serverList,
            serverStatus => $serverStatus,
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
            my $dir = $ENV{'PWD'};
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
                $res = `$dir/rock.sh $params{server_root} $file $params{commit}`;
            } else {
                $res = `$dir/rock.sh $params{server_root} $file`;
            }

            M('log')->insert({
                uid => $uid,
                server_id   =>  $params{id},
                type    =>  '2',
                res  =>  "$res",
                time    =>  \'current_timestamp'
            });

            $self->fail($res);
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
      
            my $dir = $ENV{'PWD'};
            my $now = time();
            my $file = $dir . "/mussh/hosts/pull-" . $params{id} . "-" . $now;
            
            unless (open (MYFILE, ">:utf8", $file)) {
                my $msg = '无法创建临时文件';
                $self->fail($msg);
                return;
            }

            print MYFILE join("\n", $self->param('server_address'));
            close MYFILE;

            my $res = `$dir/pull.sh $params{server_root} $file $params{repo_address}`;
            M('log')->insert({
                uid => $uid,
                server_id   =>  $params{id},
                type    =>  '1',
                res  =>  "$res",
                time    =>  \'current_timestamp'
            });
            
            $self->fail($res);
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
    $where->{server_id} = $params{id};
    my $attrs = {
        'order_by' => '-id',
        'page'  =>  $page,
        'rows_per_page' =>  $pagesize,
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


sub hard_matches {
    my $f = "," . shift . ",";
    my $s = "," . shift . ",";
    my $w = grep(/$f/, $s);
    return $w;
}


1;
