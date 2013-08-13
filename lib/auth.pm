package Auth;

use strict;
use warnings;
use Mojo::UserAgent;
use LWP::UserAgent;

sub new { bless {}, shift }

sub login {
    my ($self, $username, $password, $sign) = @_;
    
    #post login api on member
    
}
