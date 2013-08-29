package Pb::IPUB::Manage;
use Mojo::Base 'MY::Controller';
use Mojo::Util qw/encode/;
use MY::Utils;
use MY::Data;
use List::MoreUtils qw/uniq/;
use Scalar::Util qw/looks_like_number/;
use Mojo::JSON;
use JSON::XS;
use Data::Dumper;

sub add_server {
    my $self = shift;
    my $where = {};
    my $attrs = {
        'order_by'  => '-uid',
    };
    $self->set_list_data('user', $where, $attrs);
    $self->render('manage/add_server');
    return;
}

sub save_server {
    my $self = shift;
  
    if ($self->req->method eq 'POST') {
        my %params = $self->param_request({
            name => 'STRING',
            server_address => 'STRING',
            repo_address => 'STRING',
            server_root =>  'STRING',
        });

        unless ($params{name} && $params{server_address} && $params{repo_address} && $params{server_root}) {
            return $self->fail('请填写完整', go => '/manage/add_server');
        }

        my @tmpServer = split(/\r?\n/, $params{server_address});
        my $currentServer = join(',', @tmpServer);
        my $who = join(',', $self->param('who'));
        my $attention = join(',', $self->param('attention'));

        if ($who eq '') {
            $who = 0;
        }

        if ($attention eq '') {
            $attention = 0;
        }
        my $ins = $self->validation_data;
        $ins->{name} = $params{name};
        $ins->{server_address} = $currentServer;
        $ins->{repo_address} = $params{repo_address};
        $ins->{server_root} = $params{server_root};
        $ins->{who} = $who;
        $ins->{attention} = $attention;
        my $m = R('server');
        my $server = $m->insert($ins);
        my $msg = '添加成功';
        my $go = '/manage/server_list';
        $self->succ($msg, go => $go);
        return;
    }

    $self->render('manage/add_server');
    return;
}

sub server_list {
    my $self = shift;
    my %params = $self->param_request({
        page => 'UINT',
        pagesize => 'UINT',
    });

    my $page = $params{page} || 1;
    my $pagesize = $params{pagesize} || 15;
    my $servers = R('server');
    my $where = {};
    my $attrs = {
        'order_by' => '-id',
        'page'  =>  $page,
        'rows_per_page' =>  $pagesize,
    };

    my $serverStatus = {
        status_ok => $M::User::SERVER_STATUS_OK,
        status_del => $M::User::SERVER_STATUS_DELETE,
    };
    my %data = (
        serverStatus => $serverStatus,
    );
    $self->set_list_data('server', $where, $attrs);

    $self->render('manage/server_list', %data);
}

sub del_server {
    my $self = shift;
    my %params = $self->param_request({
        id  =>  'UINT',
    });

    my $server = M('server')->find({ id => $params{id} });

    if (!$server) {
        my $msg = '主机不存在';
        $self->fail($msg);
        return $self->redirect_to('/manage/server_list');
    } else {
        $server->update({ status => $M::User::SERVER_STATUS_DELETE });
        my $msg = '删除成功';
        $self->succ($msg);
        return $self->redirect_to('/manage/server_list');
    }
}

sub restore_server {
    my $self = shift;
    my %params = $self->param_request({
        id => 'UINT',
    });

    my $server = M('server')->find({ id => $params{id} });

    if (!$server) {
        my $msg = '主机不存在';
        $self->fail($msg);
        return $self->redirect_to('/manage/server_list');
    } else {
        $server->update({ status => $M::User::SERVER_STATUS_OK });
        my $msg = '恢复成功';
        $self->succ($msg);
        return $self->redirect_to('/manage/server_list');
    }
}

sub edit_server {
    my $self = shift;
    if ($self->req->method eq 'POST') {
        my %params = $self->param_request({
            id  =>  'UINT',
            name => 'STRING',
            server_address => 'STRING',
            repo_address => 'STRING',
            server_root =>  'STRING',
            status  =>  'UINT',
        });

        unless ($params{id})  {
            return $self->fail('没有主机id', go => $self->req->url);
        }

        unless ($params{name} && $params{server_address} && $params{repo_address} && $params{server_root}) {
            return $self->fail('请填写完整', go => $self->req->url);
        }

        my @tmpServer = split(/\r?\n/, $params{server_address});
        my $currentServer = join(',', @tmpServer);
        my $who = join(',', $self->param('who'));
        my $attention = join(',', $self->param('attention'));

        if ($who eq '') {
            $who = 0;
        }

        if ($attention eq '') {
            $attention = 0;
        }

        my $theServer = M('server')->find({ id => $params{id} });

        if (!$theServer) {
            my $msg_up = '主机不存在';
            $self->fail($msg_up);
            return $self->redirect_to('/manage/server_list');
        } else {
            my $upt = $self->validation_data;
            $upt->{name} = $params{name};
            $upt->{server_address} = $currentServer;
            $upt->{repo_address} = $params{repo_address};
            $upt->{server_root} = $params{server_root};
            $upt->{who} = $who;
            $upt->{status} = $params{status};
            $upt->{attention} = $attention;

            $theServer->update($upt);

            my $msg_up = '修改成功';
            $self->succ($msg_up);
            return;
        }     
    }
    
    my %params = $self->param_request({
        id  =>  'UINT',
    });

    my $server = M('server')->find({ id => $params{id} });
    if (!$server) {
        my $msg = '主机不存在';
        $self->fail($msg);
        return $self->redirect_to('/manage/server_list');
    } else {
        my $servers = join "\n", split(',', $server->{data}->{server_address});
        $server->{data}->{server_address} = $servers;
       
        my %data = (
            detail  =>  $server->{data},
            status_ok => $M::User::SERVER_STATUS_OK,
            status_del => $M::User::SERVER_STATUS_DELETE,
        );

        my $where = {};
        my $attrs = {
            'order_by'  => '-uid',
        };
        $self->set_list_data('user', $where, $attrs);
       
        $self->render('manage/edit_server', %data);
        return;
    }
}

1;
