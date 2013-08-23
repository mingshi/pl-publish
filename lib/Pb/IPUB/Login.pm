package Pb::IPUB::Login;
use Mojo::Base 'MY::Controller';
use utf8;

sub index {
    my $self = shift;

    if ($self->is_user_authenticated) {
        return $self->redirect_to($self->param('redirect_uri') || '/');
    }

    if ($self->req->method eq 'POST') {
        my $username = $self->param('username');
        my $password = $self->param('password');

        unless ($self->validate_captcha($self->param('captcha'))) {
            return $self->fail('验证码错误', go => '/login');
        }

        unless ($username && $password) {
            return $self->fail('请填写用户名和密码', go => '/login');
        }

        my $msg = {};
        unless ($self->authenticate($username, $password, $msg)) {
            return $self->fail($msg->{data} // '用户名或密码不正确', go => '/login');
        }

        return $self->done();
    }

    $self->render('login');
}

sub captcha {
    my $self = shift;
    $self->render( data => $self->create_captcha ); 
} 

1;
