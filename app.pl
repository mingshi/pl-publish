#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Mojolicious::Lite;
use Mojo::Util qw/encode decode url_escape/;
use File::Basename 'dirname';
use lib dirname(__FILE__) . '/lib';
use PB::Util;
use PB::Auth;
use Cwd 'abs_path';
use JSON::XS;
use Mojolicious::Sessions;
use Data::Dumper;

my $base_dir = abs_path(dirname(__FILE__));

under sub {
    my $self = shift;
    my $config = get_config();
    my $sessions = Mojolicious::Sessions->new;
    my $login_session_key = $config->{login_session_key};
    $sessions->cookie_name($login_session_key);
    $sessions->default_expiration(86400);
    $sessions->{$login_session_key} = 'hoho';
    if ($self->session->{user}) {
        return 1;
    } else {
        my $curr_url = $self->req->url;
        $self->redirect_to('/login?redirect_uri=' . url_escape($curr_url));
        return;
    }
};

get '/' => sub {
    my $self = shift;
    $self->render(text => 'Hello World!');
};

sub get_config{
    my $config_file = "$base_dir/config.json";
    my $config = $PB::Util::global_config;
    
    unless (-f $config_file) {
        LOG_DEBUG("Config file not found:$config_file");  
        return $config;
    }
    
    open my $fh, $config_file or return $config;
    my $content = do { local $/ = <$fh> };
    close $fh;

    eval {
        $config = decode_json($content);
    };

    $PB::Util::global_config = $config;
    return $config || {};
};

app->start;
