package Mojolicious::Plugin::FormValidation;
use Mojo::Base 'Mojolicious::Plugin';

use strict;
use warnings;
use Validate::Tiny ':all';
use Scalar::Util qw/looks_like_number/;
use Mojo::Util qw/encode decode/;
use JSON::XS;
use utf8;

our $VERSION = 0.01;

sub _regexp_check {
    my ($value, $regexp, $msg) = @_;

    return if $value ~~ [undef, ''];

    return $msg unless $value ~~ $regexp;

    return undef;
}

sub _num_cmp {
    my ($cmp_value, $cmp_name, $cmp_sub, $value, $params, $name) = @_; 

    return if $value ~~ [undef, ''];
    
    unless (looks_like_number($cmp_value)) {
        unless ($params->{$cmp_value} and looks_like_number($params->{$cmp_value})) {
            return undef;
        }

        $cmp_value = $params->{$cmp_value};
    }

    unless (looks_like_number($value)) {
        return "{$name}必须是一个数字";
    }

    unless ($cmp_sub->($value, $cmp_value)) {
        return "{$name}必须${cmp_name}${cmp_value}";
    }

    return undef;
}

sub register{
    my ( $self, $app, $options ) = @_;
    
    $options //= {};

    my %default_funs = (
        numeric => sub {
            _regexp_check($_[0], qr/^[\-+]?[0-9]*\.?[0-9]+$/, "{$_[2]}必须是一个数字"); 
        },

        integer => sub {
            _regexp_check($_[0], qr/^[\-+]?[0-9]+$/, "{$_[2]}必须是一个整数"); 
        },

        alpha => sub {
            _regexp_check($_[0], qr/^[a-z]+$/i, "{$_[2]}只能包含英文字母"); 
        },

        alpha_numeric => sub {
            _regexp_check($_[0], qr/^[a-z0-9]+$/i, "{$_[2]}只能包含数字和字母");
        },

        alpha_dash => sub {
            _regexp_check($_[0], qr/^([-a-z0-9_-])+$/i, "{$_[2]}只能包含字母、数字及下划线");
        },

        natural => sub {
            _regexp_check($_[0], qr/^[0-9]+$/, "{$_[2]}必须是一个自然数");
        },

        natural_no_zero => sub {
            my $msg = "{$_[2]}必须是一个大于0的自然数"; 
            my $ret = _regexp_check($_[0], qr/^[0-9]+$/, $msg);

            if ($ret ~~ undef and $_[0] eq '0') {
                return $msg;
            }

            return undef;
        },
    
        valid_email => sub {
            _regexp_check(
                $_[0], 
                qr/^([a-z0-9\+_\-]+)(\.[a-z0-9\+_\-]+)*@([a-z0-9\-]+\.)+[a-z]{2,6}$/ix, 
                "{$_[2]}不是一个合法的email地址"
            );
        },

        valid_emails => sub {
            return if $_[0] ~~ [undef, '']; 

            for my $email (split /\s*,\s*/, $_[0]) {
                unless ($email ~~ qr/^([a-z0-9\+_\-]+)(\.[a-z0-9\+_\-]+)*@([a-z0-9\-]+\.)+[a-z]{2,6}$/ix) { 
                    return "{$_[2]}包含不合法的email地址"
                }
            }

            return undef;
        },

        lt => sub {
            my $value = shift; 

            return sub {
                return _num_cmp($value, '小于', sub { $_[0] < $_[1] }, @_); 
            };
        },

        le => sub {
            my $value = shift; 

            return sub {

                return _num_cmp($value, '小于等于', sub { $_[0] <= $_[1] }, @_); 
            };
        },

        gt => sub {
            my $value = shift;

            return sub {

                return _num_cmp($value, '大于', sub { $_[0] > $_[1] }, @_); 
            };

        },

        ge => sub {
            my $value = shift;

            return sub {
                
                return _num_cmp($value, '大于等于', sub { $_[0] >= $_[1] }, @_); 
            };

        },

        valid_url => sub {
            return if $_[0] ~~ [undef, ''];

            my $re = qr/^(http|https|ftp):\/\/([A-Z0-9][A-Z0-9_-]*(?:\.[A-Z0-9][A-Z0-9_-]*)+):?(\d+)?\/?/i;

            unless ($_[0] ~~ $re) {
                return "{$_[2]}不是一个合法的URL地址";
            }

            return undef;
        },

        any => sub {
            return undef;
        },

        valid_json => sub {
            return if $_[0] ~~ [undef, ''];

            my $json;

            my $content = $_[0];

            #去掉注释
            $content =~ s{//[^"]+?$}{}mg;

            if (utf8::is_utf8($content)) {
                $content = encode('UTF-8', $content); 
            }

            eval {
                $json = decode_json($content);
            };

            unless ($json) {
                my $err_info = '';

                if ($@) {
                    my ($offset) = $@ =~ /offset\s*(\d+)/;
                    
                    my $sub_content = substr($content, 0, $offset + 1);
                    my $char = substr(decode('UTF-8', substr($content, $offset)), 0, 1); 
                    my $line = scalar(split("\n", $sub_content));

                    $err_info = "第${line}行语法错误，字符${char}";
                }

                return "{$_[2]}不是一个合法的JSON字符串（$err_info）";
            }

            return undef;
        },

        %{ $options->{checks} // {} },
    );

    $app->helper( form_validation => sub{
        my ($self, $rules, $funs) = @_; 

        my %funs = (
            %default_funs,        
            %{ $funs // {} }
        );
        my @validation_rules = ();
        my @validation_filters = ();
        my %labels = ();
        my %input = ();

        my %check_adapter = (
            required => {
                target => \&is_required,
                msg => '{%s}不能为空',
            },
            required_if => {
                target => \&is_required_if,
                argv_num => 1,
                argv_processor => sub {
                    return $funs{+shift};
                },
                msg => '{%s}不能为空',
            },
            equal => {
                target => \&is_equal,
                argv_num => 1,
                msg => '{%s}和{%s}不相等',
            },
            long_between => {
                target => \&is_long_between,
                argv_num => 2,
                msg => '{%s}的长度要在%s,%s之间',
            },
            long_at_least => {
                target => \&is_long_at_least,
                argv_num => 1,
                msg => '{%s}的长度最小为%s',
            },
            long_at_most => {
                target => \&is_long_at_most,
                argv_num => 1,
                msg => '{%s}的长度最大为%s',
            },
            like => {
                target => \&is_like,
                argv_num => 1,
                argv_processor => sub { my $regexp = shift; qr/$regexp/; },
                msg => '{%s}的格式错误',
            },
            in => {
                target => \&is_in,
                argv_num => -1,
                argv_processor => sub { [ @_ ] },
                msg => '{%s}的值不被允许',
            }
        );

        my $array_item_count = 0;

        for (my $i = 0; $i <= $#{$rules}; $i += 2) {
            my $key = $rules->[$i];
            my $field_rules = $rules->[$i + 1];

            my ($name, $label) = split /\|/, $key;
            $label //= $name;

            my @rules;
            
            unless (ref $field_rules) {
                @rules = split /\|/, $field_rules;
            } else {
                @rules = @{$field_rules};
            }
            
            # 数组处理
            if (my ($base_name) = $name =~ /^(.+)\[\]$/) {
                my @values = $self->param($base_name);

                if ($array_item_count == 0) {
                    $array_item_count = scalar(@values) || 1;
                }

                my $item_index = $array_item_count - 1;
                $name = $base_name . '[' . $item_index . ']';
                $input{$name} = $values[$item_index] // '';

            } else {
                $input{$name} = $self->req->body_params->param($name) //
                                $self->req->url->query->param($name) // '';
            }

            $labels{$name} = $label;

            for my $rule (@rules) {
                my ($check, $params) = $rule =~ /^(\w+)(?:\((.+)\))?/;

                my @params = ();
                unless ($params ~~ [undef, '']) {
                    @params = map { s/^\s+|\s+$//g; $_ } split /,/, $params;
                }
            
                if ($check_adapter{$check}) {
                    my $adapter = $check_adapter{$check};
                    my $need_argv_num = $adapter->{argv_num} // 0;
                    my $argv_num = scalar @params;
                    
                    if ( ($need_argv_num > 0 and $argv_num != $need_argv_num) or
                         ($need_argv_num < 0 and $argv_num == 0)
                    ) {
                        $app->log->error("form validation $check parameter error");
                        return 0;
                    }

                    my $error_msg = sprintf($adapter->{msg}, $name, @params);

                    if ($need_argv_num and $adapter->{argv_processor}) {
                        @params = $adapter->{argv_processor}(@params);
                    }

                    push @validation_rules, $name => $adapter->{target}(@params, $error_msg);

                    next;
                }

                if ($check ~~ /^trim|strip|lc|uc|ucfirst$/) {
                    push @validation_filters, $name => filter($check);
                    next;
                }

                if ($check ~~ /^filter_/) {
                    unless ($funs{$check}) {
                        $app->log->error("form validation filter $check not found");
                        return 0;
                    }

                    push @validation_filters, $name => $funs{$check};
                }

                # default custom check
                unless ($funs{$check}) {
                    $app->log->error("form validation check $check not found");
                    return 0;
                }
                
                my $check_fun = $funs{$check};
                
                if (@params) {
                    $check_fun = $check_fun->(@params);    
                }

                unless (ref $check_fun eq 'CODE') {
                    $app->log->error("form validation check $check parameter error");
                    return 0;
                }

                push @validation_rules, $name => $check_fun;
            }

            if ($array_item_count > 0) {
                $array_item_count--;
                if ($array_item_count > 0) {
                    redo;
                }
            }
        }

        if ($options->{global_filter_names}) {
            push @validation_filters, qr/.+/ => filter(@{$options->{global_filter_names}});
        }

        my $result = Validate::Tiny->new(\%input, {
            fields => [keys %labels],
            filters => \@validation_filters,
            checks  => \@validation_rules,
        });

        $self->stash({
            _form_validation_result => $result,
            _form_validation_labels => \%labels,
        });

        return $result->success;
    } );

    $app->helper( set_error_delimiters => sub {
        my ($self, $prefix, $suffix) = @_;

        $self->stash({
            _form_validation_error_prefix => $prefix,
            _form_validation_error_suffix => $suffix,
        });
    } );

    $app->helper( validation_error => sub {
        my ($self, $name) = @_;
        my $result = $self->stash('_form_validation_result');

        return '' unless $result and !$result->success;

        my $prefix = $self->stash('_form_validation_error_prefix') // '<div class="error">';
        my $suffix = $self->stash('_form_validation_error_suffix') // '</div>';

        my $errors = $result->error($name);
        my $labels = $self->stash('_form_validation_labels');

        unless (ref $errors) {
            $errors = { $name => $errors };
        }

        my @errors = ();

        for my $name (keys %{$errors}) {
            my $error = $errors->{$name};

            $error =~ s/\{(.+?)\}/$labels->{$1}/ge;
            
            push @errors, "$prefix $error $suffix";
        }

        return join "\n", @errors;
    } );

    $app->helper( validation_data => sub {
        my ($self, $name) = @_;
        my $result = $self->stash('_form_validation_result');

        return undef unless $result and $result->success;
        
        my $data = $result->data;
        
        map {
            my ($base_name, $index) = $_ =~ /^(.+)\[(\d+)\]$/;
            $data->{$base_name} //= [];
            $data->{$base_name}[$index] = delete $data->{$_};
        } grep /\[\d+\]$/, keys %$data;
        
        return $name ? $data->{$name} : $data;
    } );
}

1;
