package PB::Auth;

use strict;
use warnings;
use Mojo::UserAgent;
use Digest::MD5 qw/md5_hex/;
use Data::Dumper;
use Mojo::Util qw/encode decode url_escape/;
use JSON::XS;
use PB::Util;

sub login {
    die("1111");

    #post login api on member
    my $ua = Mojo::UserAgent->new;
    return 1;
}

1;
