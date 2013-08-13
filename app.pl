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

my $base_dir = abs_path(dirname(__FILE__));

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

    return $config || {};
};

$PB::Util::global_config = get_config();

app->start;
