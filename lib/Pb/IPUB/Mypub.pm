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
    my $attrs = {
        'order_by'  =>  '-id',  
    };
    $self->set_list_data('server', $where, $attrs);
    $self->render('mypub_list');
    return;
}

1;
