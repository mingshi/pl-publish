package Pb::IPUB::Index;
use Mojo::Base 'MY::Controller';
use utf8;

sub index {
    my $self = shift;
    $self->render_text('welcome');
}

1;
