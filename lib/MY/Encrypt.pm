package MY::Encrypt;
use utf8;
use Crypt::ECB qw(encrypt decrypt encrypt_hex decrypt_hex PADDING_AUTO);
use Mojo::Util qw(encode decode);

my $key = '!!ItsABadKey!!';
my $cipher = 'Blowfish';

sub encode {
    my $text = shift; 

    $text = encode('UTF-8', $text) if utf8::is_utf8($text); 

    return encrypt_hex($key, $cipher, $text, PADDING_AUTO); 
}

sub decode {
    my $hexcode = shift; 

    my $text = decrypt_hex($key, $cipher, $hexcode, PADDING_AUTO);

    return $text;
}
1;
