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
    $self->render('manage/add_server');
    return;
}

sub save_server {
    my $self = shift;
   
    if ($self->req->method eq 'POST') {
        my %params = $self->param_request({
            name => 'STRING',
            server_address => 'STRING',
            repo_address => 'STRING'
        });

        unless ($params{name} || $params{server_address} || $params{repo_address}) {
            return $self->fail('请填写完整', go => '/manage/add_server');
        }

        my $ins = $self->validation_data;
        $ins->{name} = $params{name};
        $ins->{server_address} = $params{server_address};
        $ins->{repo_address} = $params{repo_address};
        my $m = R('server');
        my $server = $m->insert($ins);
        my $msg = '添加成功';
        my $go = '/';
        $self->succ($msg);
        return;
    }

    $self->render('manage/add_server');
    return;
}
1;
