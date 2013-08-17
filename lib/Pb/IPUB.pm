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
        if (my $controller = $self->match->captures->{'controller'}) {
            my $module = $self->match->root->namespaces->[0] . '::' . camelize($controller);
            my $action = $self->match->captures->{'action'};

            unless ($module ~~ /^\w(?:[\w:']*\w)?$/
                and ($module->can('new') || eval "require $module; 1")
                and $module->can($action)
                and $action !~ /^_/
            ) {
                $self->render_not_found;
                return;
            }

        }

        if ($path ~~ m{^/login}) {
                return 1;
        }

        unless ($self->is_user_authenticated) {
            my $current_url = $self->req->url;
            my $redirect_url = '/login?redirect_uri=' . url_escape($current_url);
            $self->redirect_to($redirect_url);
            return;
        }
        
        return 1;
    });

    $r->get('/logout', sub {
        my $self = shift;
        $self->logout;

        $self->redirect_to('/login');
    });

    $r->route('/:controller/:action')->to(controller => 'index', action => 'index'); 
}

1;
