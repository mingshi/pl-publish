package Pb::IPUB;
use Mojo::Base 'Mojolicious';
use MY::Controller;
use Text::Xslate::Util qw/mark_raw/;
use Mojo::Util qw/url_escape camelize md5_sum encode/;
use Mojo::JSON;
use JSON::XS;
use MY::Utils;
use utf8;

sub startup {
    my $self = shift;

    $self->secret("Rocking yourself out of the life");
    $self->controller_class("MY::Controller");

    push @{$self->static->paths}, $self->home->rel_dir('../public');
    push @{$self->plugins->namespaces}, 'Pb::IPUB::Plugin';

    my $config = $self->plugin('Config', { file => 'config.conf' });
   
    $self->plugin('page_navigator', {
        'wrap_tag' => 'li',
        'prefix' => '<ul>',
        'suffix' => '</ul>',
        'prev_text' => '«',
        'next_text' => '»',
        'class' => '',
        'current_class' => 'active',
        'disabled_class' => 'disabled',
    });

    $self->plugin(xslate_renderer => {
        template_options => {
            html_builder_module => [ 'MY::FormHelper' ],
            module => ['Text::Xslate::Bridge::Star'],
            function => {
                cutstr => sub {
                    my ($len) = @_;
                    return sub {
                        return cutstr(shift, $len);
                    };
                },
                smart_match => sub {
                    return shift ~~ shift;
                },
                fnum => \&fnum,
                jsstr => sub {
                    return mark_raw(jsstr(shift));
                },
                encode_json => sub {
                    return mark_raw(encode_json(shift));
                },
            },
        },
    });

    $self->plugin('authentication' => {
        'session_key' => 'ipublishUser',
        'load_user' => sub {
            my ($self, $uid) = @_;

            my $user = M('user')->get_user_info($uid, $self->config->{userinfo_key}, $self->config->{userinfo_sign}, $self->config->{userinfo_url});
            return $user;
        },
        'validate_user' => sub {
            my ($self, $username, $password, $msg) = @_;
            my $login = M('user')->login($username, $password, $self->config->{login_key}, $self->config->{sign_key}, $self->config->{auth_url});
            
            if ($login->{status} == "err") {
                $msg->{data} = $login->{msg};
                return 0;
            }

            my $user_id = $login->{info}{id};

            return $user_id;
        },
    });

    $self->types->type(json => 'application/json; charset=utf-8;');

    #Router
    my $r = $self->routes;

    #Nomal route to controller
    $r = $r->under(sub {
        my $self = shift;
        my $path = $self->req->url->path;

        
    });
 
    
    
}

1;
