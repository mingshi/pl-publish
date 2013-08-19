package Pb::IPUB::Index;
use Mojo::Base 'MY::Controller';
use utf8;

sub index {
    my $self = shift;
    $self->redirect_to('/mypub');
    return;
}

1;
