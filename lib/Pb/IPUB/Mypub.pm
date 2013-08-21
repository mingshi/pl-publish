package Pb::IPUB::Mypub;
use Mojo::Base 'MY::Controller';
use Mojo::Util qw/encode/;
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
    my $serverStatus = {
        status_ok => $M::User::SERVER_STATUS_OK,
        status_del => $M::User::SERVER_STATUS_DELETE,
    };
   
    my $serverList = {};
    $self->set_list_data('server', $where, $attrs);
    for my $_data (@{$self->stash('list_data')}) {
        @{$serverList->{$_data->{id}}} = split(',', $_data->{server_address});
    }
    
    my %data = (
        serverStatus => $serverStatus,
        serverList  =>  $serverList,
    );
    $self->render('mypub_list', %data);
    return;
}

1;
