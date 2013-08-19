package Pb::IPUB::Mypub;
use Mojo::Base 'MY::Controller';
use Mojo::Util qw/encode/;
use Mojo::JSON;
use JSON::XS;
use Data::Dumper;

sub index {
    my $self = shift;
    $self->render('mypub_list');
    return;
}
1;
