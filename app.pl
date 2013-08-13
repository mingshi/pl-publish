#!/usr/bin/env perl
use Mojolicious::Lite;
use Mojo::Util qw/encode decode url_escape/;

any 'login' => sub {
    my $self = shift;
    return 1;
};

under sub {
    my $self = shift;

    unless ($self->is_login) {
        
        if ($self->param('username') && $self->param('sign') && $self->param('password')) {
            if ($self->login($self->param('username'), $self->param('password'), $self->param('sign'))) {
                return 1;
            }
        }

        my $curr_url = $self->req->url;
        $self->redirect_to('/login?redirect_uri=' . url_escape($curr_url));
        return;
    }

    return 1;
};

get '/' => sub {
    my $self = shift;
    $self->render(text => 'Hello World!');
};

app->start;
