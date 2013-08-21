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

sub do_pull {
    my $self = shift;
    if ($self->req->method eq "POST") {
        my %params = $self->param_request({
            id  => 'UINT',
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
            my $res = `$dir/pull.sh $params{repo_address} $params{server_root} $pullServers`;
            say $res;
            $self->succ($res);
            return;

        }
    }
}



sub hard_matches {
    my $f = "," . shift . ",";
    my $s = "," . shift . ",";
    my $w = grep(/$f/, $s);
    return $w;
}


1;
