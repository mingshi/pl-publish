package MY::Controller;
use Mojo::Base 'Mojolicious::Controller';
use DateTime::Format::Strptime; 
use DateTime::Duration;
use Time::Seconds;
use MY::Utils;
use DateTime;
use Scalar::Util qw/looks_like_number/;
use utf8;

has is_ajax => sub {

    return 1 if $_[0]->param('ajax') ~~ '1';

    my $h = $_[0]->req->headers->header('X-Requested-With');
    
    return $h && $h eq 'XMLHttpRequest';
};

has need_json => sub {
    my $self = shift;

    return $self->is_ajax || $self->stash('format') ~~ 'json';
};

sub new {
    my $self = shift->SUPER::new(@_);

    my $d = DateTime->now(time_zone => 'Asia/Shanghai');

    my $stash = {};
    $stash->{today} = $d->ymd;
    $stash->{yesterday} = ($d - DateTime::Duration->new(days => 1))->ymd;
    $stash->{yesterday2} = ($d - DateTime::Duration->new(days => 2))->ymd;
    $stash->{param_names} = [$self->param];
    $self->stash($stash);
    return $self;
}

sub render {
    my $self = shift;
    my $popmsg = $self->flash('POPMSG');
    
    $self->stash('__msg', $popmsg) if $popmsg;

    return $self->SUPER::render(@_);
}

sub ajax_result {
    my ($self, $result) = @_;

    $self->need_json(1);
    
    $result ? $self->succ : $self->fail;
}

sub fail {
    my ($self, $msg, %data) = @_;
    if ($self->need_json) {
        my $ret = { 
            code => -1,
            msg  => $msg,
        };
    
        $ret->{redirect_uri} = $data{go} if $data{go};

        $self->render_json($ret);

        return 1;
    }
    
    $msg = {
        type => 'error',
        msg  => $msg
    };
    
    $self->flash('POPMSG', $msg);

    if ($data{go}) {
        return $self->redirect_to($data{go});
    }
}


sub succ {
    my ($self, $msg, %data) = @_;

    if ($self->need_json) {
        my $ret = {
            code => 0,
            msg  => $msg,
        };
        
        $ret->{data} = $data{data} if $data{data};
        $ret->{redirect_uri} = $data{go} if $data{go};

        $self->render_json($ret);

        return 1;
    }

    $msg = {
        type => 'succ',
        msg  => $msg,
    };

    $self->flash('POPMSG', $msg);

    if ($data{go}) {
        $self->redirect_to($data{go});
    }
}

sub done {
    my ($self, %data) = @_;
    my $redirect_uri = $data{go};

    unless ($redirect_uri) {
        if ($self->param('redirect_uri')) {
            $redirect_uri = $self->param('redirect_uri');
        } else {
            $redirect_uri = $self->req->headers->referrer || '/';
        }
    }

    if ($data{msg}) {
        return $self->succ($data{msg}, go => $redirect_uri);
    }
    
    if ($data{err_msg}) {
        return $self->fail($data{err_msg}, go => $redirect_uri);
    }

    $self->redirect_to($redirect_uri);
}

sub param_request {
    $_[0]->_param($_[1], $_[0]);
}

sub param_get {
    $_[0]->_param($_[1], $_[0]->req->url->query);
}

sub param_post {
    $_[0]->_param($_[1], $_[0]->req->body_params);
}

sub _param {
    my ($self, $def, $obj) = @_;  

    my %out = ();

    for my $name (keys %$def) {
        my $name_def = $def->{$name};
        my $types = $name_def;
        my %type_def = (); 

        if (ref $name_def) {
            $types = shift @$name_def;
            %type_def = ( @$name_def );
        }

        my @types = split /\|/, $types;

        if ('ARRAY' ~~ @types) {
            my @vals = $obj->param($name);
            $out{$name} = \@vals;
        } else {
            $out{$name} = $obj->param($name);
        }

        next if $out{$name} ~~ undef;

        for my $val (ref $out{$name} ? @{$out{$name}} : $out{$name}) {

            for my $type (@types) {

                next if $type eq 'ARRAY';

                given (uc $type) {
                    when (/^SINT|INT|UINT|FLOAT$/) {
                        unless (looks_like_number($val)) {
                            $val = undef;
                            next;
                        }
                        continue;
                    }

                    when (/^S?INT$/) {
                        $val = int($val);
                    }

                    when ('UINT') {
                        $val = int($val);

                        if ($val < 0) {
                            $val = undef; 
                        }
                    }
                    
                    when ('FLOAT') {
                        $val += 0; 
                    }

                    when ('STRING') {
                        $val =~ s/<\/?\w+[^>]*>//g;    
                    }

                    when ('BOOL') {
                        if ($val ~~ ['0', 'false', 'FALSE', 'null', ''] or !$val) {
                            $val = 0;
                        } else {
                            $val = 1;
                        }
                    }

                    when ('REGEXP') {
                        if ($type_def{REGEXP} and $val !~ $type_def{REGEXP}) {
                            $val = undef;
                            next;
                        }
                    }

                    when ('ENUM') {
                        if ($type_def{ENUM} and not $val ~~ $type_def{ENUM}) {
                            $val = undef;
                            next;
                        }
                    }

                    default {
                        if ($type_def{$_} and not $val ~~ $type_def{$_}) {
                            $val = undef;
                            next;
                        }
                    }
                }
            }
        }
    }

    return %out;
}

sub set_list_data {
    my ($self, $table, $where, $attrs) = @_;

    my $rs = M($table)->select($where, $attrs); 

    my @items = map { $_->hashref } $rs->all;
    my $pager = $rs->pager;
    
    $self->stash({
        list_data => \@items,
        current_page => $pager->current_page,
        total_pages => $pager->last_page,
        pagination => $self->page_navigator($pager->current_page, $pager->last_page),
    });
}

sub _get_adsense_records {
    my $self = shift;

    my $date = $self->time_param;
    my $dbix = $self->dbix;

    my ($start_time, $end_time);

    if ($self->stash('hour_time')) {
        $start_time = "$date";  
        $end_time = timeadd($date, ONE_HOUR + 10 * ONE_MINUTE) . '';
    } else {
        $start_time = "$date";
        $end_time = timeadd($date, ONE_DAY + 10 * ONE_MINUTE) . '';
    }

    my $cond = {
        -and => [
            time => { '>=' => $start_time },
            time => { '<=' => $end_time },
        ],
    };
    
    if ($self->param('channel')) {
        my ($channel_name, $account) = split /#/, $self->param('channel');
        $cond->{channel} = $channel_name;
        $self->stash('channel', $cond->{channel});

        if ($account) {
            $cond->{account} = $account;
        }
    }

    my $rs = $dbix->table('adsense_data');

    $rs = $rs->search($cond)
        ->order_by('+time', '+channel');
    
    my @rows = $rs->all;
    
    $self->stash('date', $date);

    return \@rows;
}

sub _fallbacks {
  my ($self, $options, $template, $inline) = @_;

  $options->{handler} = 'ep';

  # Mode specific template
  return 1 if $self->render($options);

  # Template
  $options->{template} = $template;
  return 1 if $self->render($options);

  # Inline template
  my $stash = $self->stash;
  return unless $stash->{format} eq 'html';
  delete $stash->{$_} for qw(extends layout);
  delete $options->{template};
  return $self->render(%$options, inline => $inline, handler => 'ep');
}

sub build_curd {
    my ($class, %config) = @_;
    
    no strict 'refs';

    my $pk = $config{primary_key} // 'id';
    my $table = $config{table};
    my $database = $config{database};
    my $name = $config{name} // $table;
    my $prefix = $config{prefix} // '';
    my $base_path = $config{base_path} // $table;

    *{"${class}::${prefix}delete"} = sub {
        my $self = shift;
            
        my $id = $self->param($pk) // '';
        
        local $ENV{DBI_DATABASE} = $database if $database;

        unless ($id) {
            $self->fail('Parameter error');
            return;
        }

        my @ids = split /,/, $id;

        my @objs = M($table)->select({ $pk => \@ids })->all;

        unless(@objs) {
            $self->fail("$name 不存在");
            return;
        }

        my $on_delete = "_${prefix}on_delete";

        if ($self->can($on_delete)) {
            if (my $err_msg = $self->$on_delete(\@objs)) {
                if ($err_msg eq '1') {
                    return $self->succ("删除成功");
                }
                return $self->fail($err_msg); 
            }
        }

        $_->delete() for @objs;

        my $after_delete = "_${prefix}after_delete";
        if ($self->can($after_delete)) {
            $self->$after_delete($_->hashref) for @objs; 
        }

        $self->succ("删除成功");
    };

    *{"${class}::${prefix}list"} = sub {
        my ($self, $where, $attrs) = @_; 

        local $ENV{DBI_DATABASE} = $database if $database;

        $where //= {};
        $attrs //= {};
        
        my %params = $self->param_request({
            kw => '',
            page => 'UINT',
        });

        my $page = $params{page} || 1;
        my $pagesize = $config{list}{pagesize} // 15;    
        
        $attrs = [
            ref $attrs eq 'ARRAY' ? @$attrs : %$attrs,
            page => $page,
            rows_per_page => $pagesize,
        ];

        my $order_by_defined = 0;
        for (my $i = 0; $i <= $#{$attrs}; $i += 2) {
            if ($attrs->[$i] eq 'order_by') {
                $order_by_defined = 1; 
                last;
            }
        }

        push @$attrs, order_by => "-$pk" unless $order_by_defined;

        my $kw = $params{kw};

        # keyword 配置
        # 单个字段的搜索 keyword => 'field'
        # 多个字段的搜索 keyword => [ 'field1', 'field2' ]
        # 更复杂点的搜索 keyword => { like => 'field', '=' => 'field2' }
        my $kwc = $config{list}{keyword};

        if ($kw && $kwc) {
            my @sub_where = ();

            my $like = { -like => '%' . $kw . '%' };

            my $like_fields = ref $kwc eq 'HASH' ? $kwc->{like} : $kwc;
            $like_fields = [ $like_fields ] unless ref $like_fields;

            for my $like_field (@$like_fields) {
                push @sub_where, { $like_field => $like };
            }
            
            if (ref $kwc eq 'HASH' and $kwc->{'='}) {
                push @sub_where, { $kwc->{'='} => $kw };
            }

            if ($kwc->{code}) {
                my $kw_conds = $kwc->{code}->($kw);
                push @sub_where, @$kw_conds if $kw_conds;
            }

            if (ref $where eq 'ARRAY' ? scalar(@$where) : scalar(keys(%$where))) {
                $where = [
                    -and => [
                        $where,
                        \@sub_where,
                    ],
                ];
            } else {
                $where = \@sub_where;
            }
        }
        
        my $on_list_query = "_${prefix}on_list_query";
        $self->$on_list_query($where, $attrs) if $self->can($on_list_query);

        $self->set_list_data($table, $where, $attrs);
        
        my $before_render_list = "_${prefix}before_render_list";
        $self->can($before_render_list) and $self->$before_render_list;
    };

    *{"${class}::${prefix}get"} = sub {
        my $self = shift;
        
        local $ENV{DBI_DATABASE} = $database if $database;

        my %params = $self->param_get({
            $pk => 'UINT',
        });

        if ($params{$pk}) {
            my $obj = M($table)->find($params{$pk}); 

            if ($obj) {
                return $self->succ('ok', data => $obj->hashref);
            }
        }
        
        $self->fail('nil');
    };

    *{"${class}::${prefix}edit"} = sub {
        my $self = shift;
        
        local $ENV{DBI_DATABASE} = $database if $database;

        my %params = $self->param_get({
            $pk => 'UINT',
            copy_id => 'UINT',
        });

        if ($params{$pk}) {
            my $obj = M($table)->find($params{$pk}); 

            $self->stash({
                $table => $obj->hashref,
            });
        } elsif ($params{copy_id}) {
            my $obj = M($table)->find($params{copy_id}); 

            if ($obj) {
                $obj = $obj->hashref;
                delete($obj->{$pk});

                $self->stash({
                    $table => $obj,
                });
            }
        }

        my $before_render_edit = "_${prefix}before_render_edit";
        $self->can($before_render_edit) and $self->$before_render_edit;
    };

    *{"${class}::${prefix}save"} = sub {
        my $self = shift;

        local $ENV{DBI_DATABASE} = $database if $database;

        my $m = R($table); 

        my $rules = $config{rules};
        my $checks = $config{checks};

        unless ($self->form_validation($rules, $checks)) {

            return $self->fail($self->validation_error);
        }

        my $upt = $self->validation_data;
        
        my $id = delete $upt->{$pk};

        my ($obj, $msg);
        my $go = $config{save_succ_redirect};

        my $on_save = "_${prefix}on_save";
        $self->$on_save($upt, $id) if $self->can($on_save);

        if ($id and $obj = $m->find($id)) {
            $obj->update($upt);
            $msg = '保存成功';
        } else {
            $obj = $m->insert($upt);
            $id = $obj->$pk;
            $msg = "创建${name}成功";

            unless ($go) {
                $go = "/$base_path/${prefix}edit?$pk=$id";
            }
        }
        
        $upt->{id} = $id;
        my $after_save = "_${prefix}after_save";
        $self->$after_save($obj->hashref) if $self->can($after_save);

        $self->succ($msg, go => $go);
    };

    if ($config{single_editable_fields}) {
        for my $field (@{$config{single_editable_fields}}) {
            *{"${class}::${prefix}save_${field}"} = sub {
                my $self = shift;

                my $rules = $config{rules} || [];
                my $checks = $config{checks};
                my $field_name = $field;

                my $field_rule = [
                    $pk => "integer|exists_row($table)",
                ];
                
                for (my $i = 0; $i <= $#{$rules}; $i++) {
                    my ($rfield, $rname) = split /\|/, $rules->[$i];

                    if ($rfield ~~ $field) {
                        push @$field_rule, $rules->[$i], $rules->[$i + 1];
                        $field_name = $rname || $rfield;
                        last;
                    }
                }
                
                unless (scalar @$field_rule == 4) {
                    push @$field_rule, $field => 'required';
                }

                unless ($self->form_validation($field_rule, $checks)) {

                    return $self->fail($self->validation_error);
                }

                my $upt = $self->validation_data;
                
                my $id = delete $upt->{$pk};
                
                my $obj = M($table)->find($id);

                my $method = "_${prefix}on_save_${field}";
                if ($self->can($method)) {
                    if (my $msg = $self->$method($obj->hashref)) {
                        if ($msg eq '1') {
                            return $self->succ("更新${field_name}成功");
                        }

                        return $self->fail($msg);
                    }
                }

                $obj->update($upt);

                my $after_save = "_${prefix}after_save_${field}";
                $self->$after_save($obj->hashref) if $self->can($after_save);

                return $self->succ("更新${field_name}成功");
            };
        }
    }
}
1;
