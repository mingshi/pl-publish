package Pb::IPUB;
use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use MY::Controller;
use Text::Xslate::Util qw/mark_raw/;
use Mojo::Util qw/url_escape camelize md5_sum encode/;
use Pb::IPUB::Mypub;
use Mojo::JSON;
use M::User;
use JSON::XS;
use MY::Utils;
use utf8;
use Pb::IPUB::Mypub;

$M::User::SERVER_STATUS_OK = 1;
$M::User::SERVER_STATUS_DELETE = 0;

sub startup {
    my $self = shift;
    
    my @localHost = ("mingshi-hacking.local","hahhaha");
   
    my $hostName = `uname -a|awk '{print \$2}'`;
    chomp($hostName);

    #foreach (@localHost) {
    #    print($_);
    #    print($hostName);
    #    if ("$hostName" eq "$_") {
    #        print('dede');
    #    }
    #}
    #
    #
    #
    #map { if ($hostName eq $_) { print "11111"}} @localHost;

    #print( grep /^$hostName$/, @localHost );

    if (@localHost ~~ /^$hostName$/) {
        $ENV{ENV} = 'local';
    } else {
        $ENV{ENV} = 'product';
    }


    #if (grep {$_ eq "$hostName"} @localHost) {
    #    print('11111');
    #}


    $self->secret("Rocking yourself out of the life");
    $self->controller_class("MY::Controller");

    push @{$self->static->paths}, $self->home->rel_dir('../public');
    push @{$self->plugins->namespaces}, 'Pb::IPUB::Plugin';

    my $config = $self->plugin('Config', { file => 'config.conf' });
    $ENV{DBI_DATABASE} = 'ipublish';
    $ENV{DBI_USER} = 'root';
    if ($ENV{ENV} eq "local") {
        $ENV{DBI_PASSWORD} = '';
    } else {
        $ENV{DBI_PASSWORD} = 'thisisme!';
    }
    $ENV{DBI_HOST} = '127.0.0.1';

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

    $self->plugin('captcha' => {
            session_name => 'captcha_publish',
            out => {force => 'jpeg'},
            particle => [100,1],
            create => [qw/normal rect/],
            new => {
                rnd_data => ['A'...'Z'],
                rndmax => 4,
                width => 80,
                height => 30,
                lines => 1,
                gd_font => 'giant',
            }
        }
    );

    $self->plugin('form_validation', {
        global_filter_names => ['trim'],
        checks => {
            exists_row => sub {
                my ($table, $pk) = @_;
                my $database;
                $pk //= 'id';

                ($database, $table) = $table =~ /^(?:(\w+)\.)?(\w+)$/;

                return sub {
                    return if $_[0] ~~ [undef, ''];

                    my $count = M($table, $database)->select_count({
                        $pk => $_[0],
                    });

                    if ($count <= 0) {
                        return "{$_[2]}不存在";
                    }

                    return undef;
                }; 
            },

            exists_rows => sub {
                my ($table, $pk) = @_;
                my $database;
                $pk //= 'id';

                ($database, $table) = $table =~ /^(?:(\w+)\.)?(\w+)$/;

                return sub {
                    return if $_[0] ~~ [undef, ''];

                    my @ids = split /,/, $_[0];

                    my $count = M($table, $database)->select_count({
                        $pk => \@ids,
                    });

                    if ($count < scalar(@ids)) {
                        return "{$_[2]}不存在";
                    }

                    return undef;
                };

            },

            uniq_row => sub {
                my ($table, $col, $pk) = @_;
                my $database;
                $pk //= 'id';

                ($database, $table) = $table =~ /^(?:(\w+)\.)?(\w+)$/;

                return sub {
                    return if $_[0] ~~ [undef, ''];

                    $col //= $_[2];

                    my $where = {
                        $col => $_[0],
                    };

                    if ($_[1]->{$pk}) {
                        $where->{$pk} = { '!=' => $_[1]->{$pk} };
                    }

                    if (M($table, $database)->select_count($where) > 0) {

                        return "{$_[2]}已存在";
                    }

                    return undef;
                };
            },

            valid_filter => sub {
                return if $_[0] ~~ [undef, ''];

                my $content = $_[0];

                my $json = my_decode_json($content);

                if ($json->{filter}) {
                    my $err_msg;

                    unless ($self->check_filter_syntax($json->{filter}, $err_msg)) {
                        return $err_msg;
                    }
                }

                if ($json->{ext_filter}) {
                    my $err_msg;

                    unless ($self->check_filter_syntax($json->{ext_filter}, $err_msg)) {
                        return $err_msg;
                    }
                }

                if ($json->{rw_filter}) {
                    my $err_msg;

                    unless ($self->check_filter_syntax($json->{rw_filter}, $err_msg)) {
                        return $err_msg;
                    }
                }
                return undef;
            },

            valid_cond => sub {
                return if $_[0] ~~ [undef, ''];

                my $content = $_[0];

                my $json = my_decode_json($content);

                if ($json->{_cond}) {
                    my $err_msg;

                    unless (ref $json->{_cond} ~~ 'ARRAY') {

                        return '定向自定义配置语法错误，_cond 字段必须是一个数组';
                    }

                    push @{$json->{_cond}}, [ "result", "=", "1" ];

                    unless ($self->check_filter_syntax($json->{_cond}, $err_msg)) {
                        return $err_msg;
                    }
                }

                return undef;
            }
        },
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
                hard_match => sub {
                    my $f = "," . shift . ",";
                    my $s = "," . shift . ",";
                    my $w = grep(/$f/, $s);
                    return $w;  
                },
                sweet_input => sub {
                    my $str = shift;
                    my $s = "";
                    for my $address (split(',', $str)) {
                        $s .= '<input type="checkbox" value="'.$address.'" name="server_address" />'.$address."\n";
                    }
                    return $s;
                },
                hard_replace => sub {
                    my $str = shift;
                    $str =~ s/\<br \/\>/\n/g;
                    return $str;
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
        'session_key' => $self->config->{login_session_key},
        'load_user' => sub {
            my ($self, $uid) = @_;

            my $user = M::User::get_user_info($uid, $self->config->{userinfo_key}, $self->config->{userinfo_sign}, $self->config->{userinfo_url});
            return $user;
        },
        'validate_user' => sub {
            my ($self, $username, $password, $msg) = @_;
            my $login = M::User::login($username, $password, $self->config->{login_key}, $self->config->{sign_key}, $self->config->{auth_url});
          
            if ($login->{status} eq "err") {
                $msg->{data} = $login->{msg};
                return 0;
            }

            my $user_id = $login->{info}{id};
            my $ip = $self->tx->remote_address;

            my $myUser = M('user')->find({ uid => $user_id });
            
            if ($myUser) {
               $myUser->update({
                    login_time => \'current_timestamp',
                    login_ip => $ip,
                }); 
            } else {
                M('user')->insert({
                    uid => $user_id,
                    username => $login->{info}{username},
                    realname => $login->{info}{realname},
                    login_time => \'current_timestamp',
                    login_ip => $ip,
                });
            }
            
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
        if (my $controller = $self->match->{captures}{'controller'}) {
            my $module = $self->match->root->namespaces->[0] . '::' . camelize($controller);
            my $action = $self->match->{captures}{'action'};

            unless ($module ~~ /^\w(?:[\w:']*\w)?$/
                and ($module->can('new') || eval "require $module; 1")
                and $module->can($action)
                and $action !~ /^_/
            ) {
                $self->render_not_found;
                return;
            }

            if ($controller ~~ /^manage$/ && $self->current_user->{info}{is_admin} != 1) {
                return 0;
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
