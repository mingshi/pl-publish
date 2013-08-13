package PB::Auth;

use strict;
use warnings;
use Mojo::UserAgent;
use Digest::MD5 qw/md5_hex/;

sub login {
    my ($username, $password, $sign) = @_;
    
    #post login api on member
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->post(
         
    );
}
