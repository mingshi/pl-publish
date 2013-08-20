package M::User;
use Mojo::Base 'M::Base';
use Mojo::Util qw/md5_sum/;
use Tie::IxHash;
use Mojo::UserAgent;
use Mojo::Util qw/encode decode url_escape/;
use JSON::XS;
use strict;
use warnings;
use utf8;



has table => 'user';

sub password_hash {
    my ($password, $signKey) = @_;

    return md5_sum($signKey . md5_sum($password));
};

sub login_hash {
    my ($username, $password, $key, $signKey) = @_;

    my $tmpPassword = password_hash($password, $signKey);

    my $tmpUri = "key=" . $key . "&password=" . $tmpPassword . "&username=" . $username;

    return md5_sum($tmpUri);
};

sub login {
    my ($username, $password, $key, $signKey, $authUrl) = @_;

    my $sign = login_hash($username, $password, $key, $signKey);
    my $tmpPass = password_hash($password, $signKey);
    my $ua = Mojo::UserAgent->new;

    my $res = $ua->post(
        $authUrl,
        form => { username => $username, password => $tmpPass, sign => $sign }
    );
 
    my $tmpRes = decode_json($res->res->body);
 
    return $tmpRes;
};

sub user_info_sign {
    my ($uid, $sign) = @_;
    my $tmpUri = "key=" . $sign . "&uid=" . $uid;
    return md5_sum($tmpUri);
}

sub get_user_info {
    my ($uid, $key, $sign, $userinfoUrl) = @_;
    my $tmpSign = user_info_sign($uid, $sign);

    my $ua = Mojo::UserAgent->new;
    my $res = $ua->post(
        $userinfoUrl,
        form => { uid => $uid, key => $key, sign => $tmpSign }
    );

    my $tmpRes = decode_json($res->res->body);

    return $tmpRes;
};
1;
