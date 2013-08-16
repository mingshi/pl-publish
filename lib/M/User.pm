package M::User;
use Mojo::Base 'M::Base';
use Mojo::Util qw/md5_sum/;
use Tie::IxHash;
use Mojo::UserAgent;
use Mojo::Util qw/encode decode url_escape/;
use strict;
use warnings;
use utf8;

sub password_hash {
    my ($self, $password, $signKey) = @_;

    return md5_sum($signKey . md5_sum($password));
};

sub login_hash {
    my ($self, $username, $password, $key, $signKey) = @_;

    my $tmpPassword = $self->password_hash($password, $signKey);

    my $tmpUri = "key=" . $key . "&password=" . $tmpPassword . "&username=" . $username;

    return md5_sum($tmpUri);
};

sub login {
    my ($self, $username, $password, $key, $signKey, $authUrl) = @_;

    my $sign = $self->login_hash($username, $password, $key, $signKey);
    my $ua = Mojo::UserAgent->new;

    my $res = $ua->post(
        $authUrl,
        form => { username => $username, password => $password, sign => $sign }
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
    my ($self, $uid, $key, $sign, $userinfoUrl) = @_;
    $tmpSign = $self->user_info_sign($uid, $sign);

    my $ua = Mojo::UserAgent->new;
    my $res = $ua->post(
        $userinfoUrl,
        form => { uid => $uid, key => $key, sign => $tmpSign }
    );

    my $tmpRes = decode_json($res->res->body);

    return $tmpRes;
};
1;
