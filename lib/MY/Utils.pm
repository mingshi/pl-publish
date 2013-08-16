package MY::Utils;
use Modern::Perl;
use Mojo::Util qw/encode decode camelize/;
use Exporter 'import';
use DateTime;
use Time::Seconds;
use List::MoreUtils qw/minmax uniq/;
use File::Basename qw/dirname/;
use File::Path qw/make_path/;
use Data::Dumper;
use Time::HiRes;
use MaterialHtml;
use Log::Fast;
use JSON::XS;
use POSIX ();
use Fcntl qw/:flock/;
use utf8;

use constant {
    ADSENSE_START_HOUR => 15,
    ADSENSE_START_DELAY_HOUR => 17,
};

our @EXPORT = qw/
cutstr trim jsstr fnum timeadd 
get_dbix M R
strtodatetime strtotime strftime
set_summary set_cpc set_cpm set_ctr set_rate sum
extend_row
adsense_daily_report adsense_hourly_report
adsense_slot_report
get_slot_ads array2hash array_get_column
my_decode_json
build_slot_data build_ad_data
get_log LOG
var_dump microtime
is_null_datetime
check_script_singleton
/;

sub get_log {
    my ($log_file, $level, $cate) = @_; 

    my $log_config = {
        level   => 'DEBUG',
        prefix  => '%D %T [' . ($cate // 'DEFAULT') . '] [%L] ',
        type    => 'fh',
        fh      => \*STDOUT, 
        level => $level|| 'INFO'
    };

    if ($log_file) {
        eval {
            $log_file = strftime($log_file); 
            my $log_dir = dirname($log_file);
            
            unless (-d $log_dir) {
                make_path($log_dir);
            }

            if (open my $fh, ">>$log_file") {
                $log_config->{fh} = $fh;
            }
        };
    }

    Log::Fast->new($log_config);
}

sub LOG {
    state $LOG;

    unless ($LOG) {
        my ($log_file, $level) = (undef, 'INFO');  

        if ($ENV{GGXT_MODE} ~~ 'development') {
            $level = 'DEBUG'; 
        } else {
            $log_file = '/var/hosts/logs/default/%Y%m%d.log';
            $level = 'ERR';
        }

        $log_file = $ENV{GGXT_LOG_FILE} // $log_file;
        $level = $ENV{GGXT_LOG_LEVEL} // $level;

        $LOG = get_log($log_file, $level, $ENV{GGXT_LOG_CATE});
    }

    return $LOG;
}

sub _get_config_value {
    my ($val, $slot) = @_;

    unless (ref $val) {
        my ($ref_key) = $val =~ /^ref\.(.+)$/;
        if ($ref_key) {
            $val = $slot->{$ref_key};
        }
    }

    return $val;
}

sub my_decode_json {
    my ($content) = @_;

    $content =~ s{//[^"]+?$}{}gm;

    $content = encode('UTF-8', $content) if utf8::is_utf8($content);

    return decode_json($content);
}

sub build_slot_data
{
    my ($slot_id, $serialize_in_json) = (@_);
    
    local $ENV{DBI_DATABASE} = 'ad_core';

    my $slot = R('slot')->find($slot_id);

    return undef unless $slot;

    my $data = $slot->config ? my_decode_json($slot->config) : {};

    $data = {
        #_name => $slot->name,
        #publisher_id => 0,
        ad => $slot->default_ad + 0,
        width => $slot->width + 0,
        height => $slot->height + 0,
        _nfid => 'g' . $slot->group_id,
        #snyu => $slot->send_mail + 0,
        #cpm => [$slot->min_cpm + 0, $slot->max_cpm + 0],
        %$data,
    };

    #弹窗设置名称适配
    my @pop_name_fix = (
        'isBack' => 'ik',
        'is_back' => 'ik',
        'useHack' => 'uk',
        'use_hack' => 'uk',
        'interval' => 'il',
        'url' => 'ul',
        'superBlur' => 'sbr',
        'superblur' => 'sbr',
        'super_blur' => 'sbr',
        'when' => 'wn',
        'wn.click' => 'ck',
        'wn.mousemove' => 'me',
        'wn.blur' => 'br',
        'wn.timeout' => 'tt',
        'wn.menu' => 'mu',
    );

    for my $pop_config ( 'co', 'pp' ) {
        next unless $data->{ext} && $data->{ext}{$pop_config};

        for (my $i = 0; $i <= $#pop_name_fix; $i += 2) {
            my $from = $pop_name_fix[$i];
            my $to = $pop_name_fix[$i + 1];
            
            my @tokens = split /\./, $from;
            my $temp = $data->{ext}{$pop_config};

            if (@tokens == 2) {
                next unless $temp->{$tokens[0]};
                $temp = $temp->{$tokens[0]};
                $from = $tokens[1];
            }

            if (exists $temp->{$from}) {
                $temp->{$to} = $temp->{$from};
                delete $temp->{$from};
            }
        }
    }

#    if ($slot->group_id) {
#        if (my $group = R('object_group')->find($slot->group_id)) {
#            #$data->{_group} = $group->name;
#            #$data->{publisher_id} = $group->publisher_id + 0;
#        }
#    }

    my @refs = $slot->config =~ m{ref\.([\w-]+)}g;
    my %ref_count = ();
    if (@refs) {
        for my $ref (@refs) {
            $ref_count{$ref}++;
            unless ($data->{$ref}) {
                my $rule = R('rule')->find({ name => $ref });                
                if ($rule) {
                    $data->{$ref} = my_decode_json($rule->config);
                }
            }
        }
    }
    
    if ($data->{rule} and not ref $data->{rule}) {
        if (my ($ref_rule) = $data->{rule} =~ /ref\.([\w-]+)/) {
            $data->{rule} = $data->{$ref_rule};
            if ($ref_count{$ref_rule} == 1) {
                delete $data->{$ref_rule};
            }
        }
    }

    if ($data->{pop_add_city}) {
        if (ref $data->{pop_add_city}) {
            delete $data->{pop_add_city};
        } else {
            $data->{pop_add_city} = {
                map { $_ => 1 } split(/,/, $data->{pop_add_city})
            };
        }
    }

    if ($serialize_in_json) {
        return decode('UTF-8', encode_json($data));
    }

    return $data;
}

sub build_ad_data
{
    my ($ad_id, $serialize_in_json) = (@_);
    
    local $ENV{DBI_DATABASE} = 'ad_core';

    my $ad = R('ad')->find($ad_id);

    return undef unless $ad;

    my $data; 
    
    eval {
        $data = $ad->config ? my_decode_json($ad->config) : {};
    };
    
    $data //= {};

    $data->{_name} = $ad->name;

    if ($ad->group_id) {
        if (my $group = R('object_group')->find($ad->group_id)) {
            $data->{_group} = $group->name;
        }
    }
    
    if ($ad->pv_group_id) {
        if (my $group = M('group')->get($ad->pv_group_id)) {
            M::Group::extend_config($group);
            
            $data->{_fid} = 'g' . $group->{id} if $group->{frequency};
            $data->{_ftime} = $group->{frequency_time} if $group->{frequency_time};
        }
    }

    if (!$data->{_fid} && ($ad->frequency || $ad->frequency_id)) {
        $data->{_fid} = $ad->frequency_id if $ad->frequency_id;
        $data->{_ftime} = $ad->frequency_time if $ad->frequency_time;
    }

    $data->{content} //= {};
    
    my $material_ids = $ad->material_ids || $ad->material_id; 

    if ($ad->type ~~ ['brand', 'pop'] && $material_ids) {

        my @content = ();

        $data->{union} //= 'self';

        for my $material_id (split /,/, $material_ids) {
            next unless $material_id;

            my $material = R('material')->find($material_id);
            
            next unless $material;

            my $content = $material->config ? my_decode_json($material->config) : {};
            
            $content->{mid} = int($material->id);
            $content->{type} //= $material->type;
            
            if ($material->click_url) {
                $content->{c_url} //= $material->click_url;
            }
            
            if ($material->track_url) {
                $content->{track_play} //= $material->track_url;
            }

            given ($material->type) {
                when (['image', 'flash', 'video']) {
                    $content->{url} //= material_static_url($material->upload_path);
                    $content->{width} //= int($material->width);
                    $content->{height} //= int($material->height);
                }
                when ('text') {
                    my @links = $material->content =~ /\[([^\]]+)\|([^\]\|]+)\]/g;
                    
                    if (scalar @links == 2) {
                        $content->{c_url} //= $links[0];
                        $content->{title} //= $links[1];
                    } else {
                        for (my $i = 0; $i < @links; $i += 2) {
                            $content->{link} //= [];
                            push @{$content->{link}}, [$links[$i], $links[$i + 1]];
                        }
                    }
                }
                when ('rich') {
                    #$data->{content}{html} = $material->content;
                }
            }

            my $html = MaterialHtml->new({
                material => $material->hashref,
            });

            $content->{_html} = $html->get_html; 
            $content->{_click_tags} = $html->get_click_tags;

            push @content, $content;
        }

        if (@content == 1) {
            $data->{content} = {
                %{$content[0]},
                %{$data->{content}},
            };
        } elsif (@content > 1) {
            $data->{content_list} = [];

            my $weight = 0; 
            for my $content (@content) {
                $weight += ($content->{weight} // 1);
                push @{$data->{content_list}}, [
                    $weight, $content 
                ];
            }
        }
    }

    delete $data->{_cond} if exists $data->{_cond};
    
    if (exists $data->{content}{rule} && ! ref $data->{content}{rule}) {
        if (my ($ref) = $data->{content}{rule} =~ /^ref\.([\w-]+)$/) {
            my $rule = R('rule')->find({ name => $ref });                
            if ($rule) {
                $data->{content}{rule} = my_decode_json($rule->config);
            }
        }
    }

    if ($serialize_in_json) {
        return decode('UTF-8', encode_json($data));
    }

    return $data;
}

sub get_slot_ads {
    my ($slot) = shift;

    my $err = \$_[0];

    return unless $slot;

    my @ads = ( );

    push @ads, $slot->{ad} if $slot->{ad}; 

    if (my $filters = $slot->{filter}) {
        unless (ref $filters->[0][0] eq 'ARRAY') {
            $filters = [ $filters ];
        }

        for my $filter (@$filters) {
            my $assigns = $filter->[$#{$filter}];
            unless (ref $assigns->[0] eq 'ARRAY') {
                $assigns = [$assigns];
            } else {
                #解原始引用，后面会修改这个数据
                $assigns = [ @$assigns ];
            }
            
            while (my $assign = shift @$assigns) {
                if ($assign->[0] eq 'adid') {
                    if ($assign->[1] eq '=') {
                        push @ads, $assign->[2];
                    } elsif ($assign->[1] eq '*=') {
                        for my $elem (@{$assign->[2]}) {
                            push @ads, $elem->[1];
                        }
                    }
                }

                if ($assign->[0] eq '__set') {
                    my $new_assigns = [];

                    if ($assign->[1] eq '=') {
                        $new_assigns = _get_config_value($assign->[2], $slot);      
                    } elsif ($assign->[1] eq '*=') {
                        for my $elem (@{$assign->[2]}) {
                            my $sub_assign = _get_config_value($elem->[1], $slot);
                            if (ref $sub_assign->[0] eq 'ARRAY') {
                                push @$new_assigns, @{$sub_assign};
                            } else {
                                push @$new_assigns, $sub_assign;
                            }
                        }
                    }

                    if (scalar @$new_assigns) {
                        if (ref $new_assigns->[0] eq 'ARRAY') {
                            push @$assigns, @$new_assigns;
                        } else {
                            push @$assigns, $new_assigns;
                        }
                    }
                }
            }
        }
    }
    
    @ads = uniq(@ads);

    return \@ads;
}

sub sum {
    my ($cols, $hkey) = @_;
    
    my $sum = 0;

    given (ref $cols) {
        when ('HASH') {
            for my $_ (keys %$cols) {
                $sum += $cols->{$_}{$hkey};            
            }
        }
        
        when ('ARRAY') {
            for my $_ (@$cols) {
                $sum += $_;
            }
        }
    }

    return $sum;
}

sub cutstr {
    my ($str, $len) = @_;

    $str = encode('UTF-8', $str) if utf8::is_utf8($str);

    my $i = 0;
    my $wi = 0;
    my @new_chars = ();
    my @chars = split //, $str;
    my $n = scalar @chars;
    while ($i < $n) {
        my $ord = ord($chars[$i]);
        given ($ord) {
            when ($_ > 224) {
                push @new_chars, substr($str, $i, 3);
                $i += 3;
                $wi += 2;
            }
            when ($_ > 192) {
                push @new_chars, substr($str, $i, 2);
                $i += 2;
                $wi += 2;
            }
            default {
                push @new_chars, substr($str, $i, 1);
                $i += 1;
                $wi += 1;
            }
        }
        last if $wi >= $len;
    }

    unless ($wi < $len || ($wi == $len && $i == $n)) {
        my $sub_len = 3;
        while ($sub_len > 0 && @new_chars) {
            my $char = pop(@new_chars); 
            $sub_len -= length($char);
        }
        push @new_chars, '...';
        #$new_str =~ s/(?:[\x{00}-\x{ff}]{3}|.{2})$/.../;
    }

    return decode('UTF-8', join('', @new_chars));
}

sub trim {
    my ($str, $chars) = @_;

    return $str unless $str;

    $chars //= '\\s';
    $str =~ s/^[$chars]+|[$chars]+$//g;

    return $str;
}

sub jsstr {
    my $str = shift;

    $str =~ s/"/\\"/g;

    return qq{"$str"};
}

sub fnum {
    my $input = shift;

    return 0 if $input ~~ undef;

    $input = sprintf("%.2f", $input) if $input =~ /\./;
    $input = reverse $input;
    $input =~ s<(\d\d\d)(?=\d)(?!\d*\.)><$1,>g;
    return reverse $input;
}

sub get_dbix {
    require DBIx::Lite or return;
    
    DBIx::Lite->import;

    my $database = $_[0] // $ENV{DBI_DATABASE} // 'ad_report';

    my $username = $ENV{DBI_USER} // 'root';
    my $password = $ENV{DBI_PASSWORD} // 'thisisme!';
    my $host = $ENV{DBI_HOST} // '127.0.0.1';

    if (exists $ENV{GGXT_MODE} && $ENV{GGXT_MODE} eq 'development') {
        $password = '';
    }

    return DBIx::Lite->connect(
        "dbi:mysql:$database:$host", $username, $password, 
        { 
            RaiseError => 1,
            mysql_enable_utf8 => 1
        } 
    );
}

sub R {
    my ($table, $database) = @_;
    
    my $dbix = get_dbix($database);

    return unless $dbix;

    state %schema_init;

    $dbix->schema->table($table)->autopk('id');

    return $dbix->table($table);
}

sub M {
    my $table = $_[0];
    my $package = 'M::' . camelize($table);

    eval "require $package";
    unless ($@) {
        $package->import;
        return $package->singleton;
    }

    require M::Base;
    M::Base->import;

    my $database = $_[1] // $ENV{DBI_DATABASE} // 'ad_core';
    my $m = M::Base->new; 
    $m->table($table);
    $m->database($database);
    return $m;
}

sub strtodatetime {
    my $str = shift;
    my ($y, $m, $d, $h, $i, $s) = 
        #split /\D+/, $str;
        $str =~ m/^(\d{4})\D(\d{1,2})\D(\d{1,2})(?:\D(\d{1,2}))?(?:\D(\d{1,2}))?(?:\D(\d{1,2}))?$/;

    return DateTime->new(
        year => $y,
        month => $m,
        day => $d,
        hour => $h || 0,
        minute => $i || 0,
        second => $s || 0,
        time_zone => 'Asia/Shanghai'
    );
}

sub strtotime {
    my $str = shift;
    my ($y, $m, $d, $h, $i, $s) = 
        #split /\D+/, $str;
        $str =~ m/^(\d{4})\D(\d{1,2})\D(\d{1,2})(?:\D(\d{1,2}))?(?:\D(\d{1,2}))?(?:\D(\d{1,2}))?$/;

    return POSIX::mktime(
        $s || 0,
        $i || 0,
        $h || 0,
        $d,
        $m - 1,
        $y - 1900
    );
}

#%F %T => %Y-%m-%d %H:%M:%S
sub strftime {
    my ($fmt, $time) = @_;
    
    $time //= time;

    return POSIX::strftime($fmt, localtime($time)); 
}

sub timeadd {
    my ($date, $seconds) = @_;
    return DateTime->from_epoch(
        epoch => $date->epoch + $seconds,
        time_zone => 'Asia/Shanghai'
    );
}

sub extend_row {
    my $row = shift;
=dis
    set_rate($row, 
        base => 'request',
        col => 'play',
        name => 'play_request_loss',
        revert => 1,
    );
    
    set_rate($row, 
        base => 'request',
        col => 'download',
        name => 'download_request_loss',
        revert => 1,
    );
=cut
    set_rate($row, 
        base => 'union_request',
        col => 'adsense_request',
        name => 'adsense_request_request_loss',
        revert => 1,
    );

    set_rate($row, 
        base => 'union_request',
        col => 'adsense_match_request',
        name => 'adsense_match_request_request_loss',
        revert => 1,
    );

    set_rate($row, 
        base => 'adsense_request',
        col => 'adsense_match_request',
        name => 'adsense_match_request_adsense_request_loss',
        revert => 1,
    );

    set_ctr($row, 
        pv => 'request',
        click => 'click',
        ctr => 'request_ctr',
    );

    set_ctr($row, 
        pv => 'adsense_match_request',
        click => 'adsense_click',
        ctr => 'adsense_match_request_ctr',
    );

    set_ctr($row, 
        pv => 'channel_pv',
        click => 'channel_click',
        ctr => 'channel_ctr',
    );

    if (exists $row->{brand_click}) {
        set_ctr($row,
            pv => 'brand_request',
            click => 'brand_click',
            ctr => 'brand_ctr',
        );
    }

    set_cpm($row, 
        pv => 'adsense_request',
        income => 'adsense_income',
        cpm => 'adsense_request_cpm',
    );

    set_cpm($row, 
        pv => 'adsense_match_request',
        income => 'adsense_income',
        cpm => 'adsense_match_request_cpm',
    );

    set_cpm($row, 
        pv => 'union_request',
        income => 'adsense_income',
        cpm => 'request_adsense_cpm',
    );

    set_cpm($row, 
        pv => 'request',
        income => 'channel_income',
        cpm => 'request_channel_cpm',
    );
    

    #unless (exists $row->{channel_cpm}) {
        set_cpm($row, 
            pv => 'channel_pv',
            income => 'channel_income',
            cpm => 'channel_cpm',
        );
    #}

    set_cpm($row, 
        pv => 'request',
        income => 'real_income',
        cpm => 'request_real_cpm',
    );

    return $row;
}

sub adsense_slot_report {
    my $report = shift;
    my $merge_log = shift // [];
    
    my $slot_report = {};

    my $dbix = get_dbix();
    for my $time (keys %$report) {
        my $time_int = strtotime($time);
        my $start_hour;
        my $end_hour;
# 保持和天数据一致
#        if ($time ~~ /\d{2}:\d{2}/) {
#            $start_hour = $date->strftime('%Y%m%d%H');
#            $end_hour = $start_hour;
#        } else {
            $start_hour = strftime('%Y%m%d00', $time_int);
            $end_hour = strftime('%Y%m%d23', $time_int);
#        }
        my $cond = {
            hour => [
                -and => 
                    { '>=' => $start_hour },
                    { '<=' => $end_hour },
            ],
            ad_id => { '>' => 0 },
        };

        my @rs = $dbix->table('ad_slot_hour_report')
            ->select('ad_id,slot_id,sum(play) as pv')->search($cond)
            ->group_by('ad_id', 'slot_id')
            ->having({ pv => { '>' => 0 } })
            ->order_by('-sum(play)')
            ->all();

        my $ad_to_slot = {};
        for my $row (@rs) {
            my $item = $row->hashref;
            my $ad_id = $item->{ad_id};
            my $slot_id = $item->{slot_id};
            $ad_to_slot->{$ad_id} //= {};
            $ad_to_slot->{$ad_id}{total_pv} += $item->{pv};
            $ad_to_slot->{$ad_id}{slot}{$slot_id} = $item->{pv};
        }

        my $time_report = $report->{$time};
        for my $channel (keys %$time_report) {
            my $channel_report = $time_report->{$channel};
            next if $channel_report->{request} == 0;
            next if $channel eq 'summary';
            my $income = $channel_report->{income};

            my ($ad_id) = $channel =~ /^(?:AD_)?(\d+)_/i;
            unless ($ad_id) {
                push @$merge_log, "$channel 对应不到AD，收入为 $income";
                next;
            }
           
            unless($ad_to_slot->{$ad_id}) {
                # 使用投放配置的关系
                if (my $rel = M('slot_ad')->find({ ad_id => $ad_id })) {
                    $ad_to_slot->{$ad_id} = {
                        total_pv => 1,
                        slot => {
                            $rel->slot_id => 1,
                        }
                    };
                } else {
                    push @$merge_log, "$channel 对应的AD没有系统数据，收入为 $income";
                    next;
                }
            }

            my $total_pv = $ad_to_slot->{$ad_id}{total_pv};
            my $slots = $ad_to_slot->{$ad_id}{slot};

            for my $slot_id (keys %$slots) {
                my $pv = $slots->{$slot_id}; 
                my $weight_percent = int(100 * $pv / $total_pv + 0.5);
                next unless $weight_percent;
                my $weight = $weight_percent / 100;
                my $slot = $slot_report->{$time}{$slot_id} //= {};
                my $slot_ad_data = {
                    request => int($channel_report->{request} * $weight + 0.5),
                    match_request => int($channel_report->{match_request} * $weight + 0.5),
                    click => int($channel_report->{click} * $weight + 0.5),
                    income => $channel_report->{income} * $weight,
                };

                $slot->{ads}{$ad_id} //= {};
                for my $_ ('request', 'match_request', 'click', 'income') {
                    $slot->{$_} += $slot_ad_data->{$_};
                    $slot->{ads}{$ad_id}{$_} += $slot_ad_data->{$_};
                }
                $slot->{channels} //= []; 

                push(@{$slot->{channels}}, [$channel, $weight_percent . '%']);
            }
        }
    }

    return $slot_report;
}

sub adsense_daily_report {
    my ($rows) = @_;

    my %report = ();
    my @fields = ('request', 'match_request', 'click', 'income');

    for my $row (@$rows) {
        my $channel = $row->channel . '#'. $row->account;
        my $time = strtotime($row->time);
        my $adtype = $row->adtype;

        my (undef, $time_minute, $time_hour) = localtime($time);

        if ($time_hour == 0 and $time_minute < 10) {
            my $corr_time = $time - 10 * ONE_MINUTE;
            my $corr_date = strftime('%Y-%m-%d', $corr_time);
            if (exists $report{$corr_date}) {
                $time = $corr_time;
                (undef, $time_minute, $time_hour) = localtime($time);
            }
        }
        my $date = strftime('%Y-%m-%d', $time);
        
        my $ireport = ($report{$date}{$channel}{adtype_data}{$adtype} //= {});

        my $start = $ireport->{start}; 
        my $mid = $ireport->{mid};

        unless ($start) {
            $ireport->{$_} = 0 for @fields; 
            $ireport->{start} = $row;
            $ireport->{mid} = $row;
            next;
        }
        
        if ($time_hour < ADSENSE_START_HOUR or 
            (!$ireport->{mid_fixed} and $row->request >= $mid->request)) {

            $ireport->{$_} = $row->$_ - $start->$_ for @fields;
            $ireport->{mid} = $row;
            next;
        }

        $ireport->{$_} = $mid->$_ - $start->$_ + $row->$_ for @fields;
        $ireport->{mid_fixed} = 1 unless $ireport->{mid_fixed};
    }

    for my $date ( keys %report ) {
        my $dateReport = $report{$date};

        for my $channel ( keys %$dateReport ) {
            my $channelReport = $dateReport->{$channel};
            $channelReport->{$_} = sum($channelReport->{adtype_data}, $_)
                for @fields;
        }

        my $summary = {};
        $summary->{$_} = sum($dateReport, $_) for @fields;
        $dateReport->{summary} = $summary;
    }

    return \%report;
}

sub adsense_hourly_report {
    my ($rows, $not_full_data_of_day) = @_;

    my %report = ();
    my @fields = ('request', 'match_request', 'click', 'income');
    for my $row (@$rows) {
        $row = $row->hashref;
        my $channel = $row->{channel} . '#' . $row->{account};
        my $time = strtotime($row->{time});
        my $adtype = $row->{adtype};
        my (undef, $time_minute, $time_hour) = localtime($time);

        if ($time_hour == 0 and $time_minute < 5) {
            my $corr_time = $time - 5 * ONE_MINUTE;
            my $corr_hour = strftime('%Y-%m-%d %H:00', $corr_time);
            if (exists $report{$corr_hour}) {
                $time = $corr_time;
                (undef, $time_minute, $time_hour) = localtime($time);
            }
        }

        my $hour = strftime('%Y-%m-%d %H:00', $time);
        my $prev_hour = strftime('%Y-%m-%d %H:00', $time - 5 * ONE_MINUTE); 

        my $ireport = ($report{$hour}{$channel}{adtype_data}{$adtype} //= {});

        my $start = $ireport->{start}; 

        if ($prev_hour ne $hour) {

            if (exists $report{$prev_hour} and exists $report{$prev_hour}{$channel}{adtype_data}{$adtype}) {
                my $last = $report{$prev_hour}{$channel}{adtype_data}{$adtype};   
                
                if ($time_hour < ADSENSE_START_HOUR or $row->{request} >= $last->{request}) {
                    $last->{$_} = $row->{$_} - ($last->{start} ? $last->{start}->{$_} : 0) for @fields;
                    $last->{end} = $row;
                    #$last->{end_time} = strftime('%Y-%m-%d %H:%M:%S', $time); 
                }
            }

        }

        unless ($start) {
            $ireport->{$_} = 0 for @fields; 

            # 取前一条有效记录的结束节点
            my $last_hour;
            for my $ihour (reverse sort keys %report) {
                if ($ihour ne $hour and
                    exists($report{$ihour}{$channel}) and
                    exists($report{$ihour}{$channel}{adtype_data}) and
                    exists($report{$ihour}{$channel}{adtype_data}{$adtype})
                ) {
                    $last_hour = $ihour;
                    last;
                }
            }

            if ($last_hour) {
                my $last = $report{$last_hour}{$channel}{adtype_data}{$adtype};
                my $last_row = $last->{end} || $last->{start};

                if ($time_hour < ADSENSE_START_HOUR or $last_row->{request} <= $row->{request}) {
                    $ireport->{start} = $last_row;
                    #$ireport->{start_time} = $last->{end_time} || $last->{start_time};
                }
            } 
            
            unless ($ireport->{start}) {
                # 如果每个小时采集都准确，判断是新开始的投放可以改为 < 1
                # 先保持和天报表的逻辑一致
                if ($time_hour < ADSENSE_START_HOUR or $not_full_data_of_day) {
                    $ireport->{start} = $row;
                    next;
                }
                #$ireport->{start_time} = strftime('%Y-%m-%d %H:%M:%S', $time);
            }
        }
        
        $start = $ireport->{start};

        if ($ireport->{end} && $row->{request} < $ireport->{end}{request} and 
            $time_hour > ADSENSE_START_HOUR and 
            $time_hour < ADSENSE_START_DELAY_HOUR
        ) {
            $ireport->{$_} += $row->{$_} for @fields;
        } else {
            $ireport->{$_} = $row->{$_} - ($start ? $start->{$_} : 0) for @fields;
            $ireport->{end} = $row;
        }

        #$ireport->{end_time} = strftime('%Y-%m-%d %H:%M:%S', $time);
    }

    for my $date ( keys %report ) {
        my $dateReport = $report{$date};

        for my $channel ( keys %$dateReport ) {
            my $channelReport = $dateReport->{$channel};
            $channelReport->{$_} = sum($channelReport->{adtype_data}, $_)
                for @fields;
        }
    }

    return \%report;
}

sub set_cpm {
    my ($item, %opt) = @_;

    my $na = $opt{null} // '-';
    my $pv = $opt{pv} // 'play';
    my $income = $opt{income} // 'income';
    my $cpm = $opt{cpm} // 'cpm';

    $item->{$cpm} = $item->{$pv}
    ? sprintf('%.2f', $item->{$income} * 1000 / $item->{$pv})
    : $na;

    return $item;
}

sub set_cpc {
    my ($item, %opt) = @_;

    my $na = $opt{null} // '-';
    my $click = $opt{click} // 'click';
    my $income = $opt{income} // 'income';
    my $cpc = $opt{cpc} // 'cpc';

    $item->{$cpc} = $item->{$click}
    ? sprintf('%.2f', $item->{$income} / $item->{$click})
    : $na;

    return $item;
}

sub set_ctr {
    my ($item, %opt) = @_;

    my $na = $opt{null} // '-';
    my $pv = $opt{pv} // 'play';
    my $click = $opt{click} // 'click';
    my $ctr = $opt{ctr} // 'ctr';

    $item->{$ctr} = $item->{$pv}
    ? sprintf('%.2f%%', $item->{$click} / $item->{$pv} * 100)
    : $na;

    return $item;
}

sub set_rate {
    my ($item, %opt) = @_;

    my $na = $opt{null} // '-';
    my $col = $opt{col} // 'request';
    my $base = $opt{base} // 'request';
    my $name = $opt{name} // "${col}_rate";
    my $revert = $opt{revert} // 0;

    my $rate = $item->{$base} != 0
    ? sprintf('%.2f', $item->{$col} / $item->{$base} * 100)
    : $na;
    
    if ($revert && $rate ne $na) {
        $rate = 100 - $rate;
    }

    $item->{$name} = ($rate eq $na ? $na : sprintf('%.2f%%', $rate)); 
}

sub set_summary {
    my ($rows, $columns) = @_;

    my $summary = {};
    
    for my $row (@$rows) {
        for my $column (@$columns) {
            $summary->{$column} += $row->{$column};
        }
    }

    return $summary;

}

sub array2hash {
    my ($arr, $key) = @_;

    my $hash = {};

    for my $elem (@$arr) {
        if (ref $elem) {
            if (exists $elem->{$key}) {
                $hash->{$elem->{$key}} = $elem;
            } else {
                $hash->{$elem->$key} = $elem;
            }
        }
    }

    return $hash;
}

sub array_get_column {
    my ($arr, $key) = @_;

    my @column = map { $_->{$key} } @$arr;

    return \@column;
}

sub check_alarm_rule {
    my ($rules, $data) = @_; 

    return undef unless ref $rules eq 'ARRAY';

    $rules = [ $rules ] unless ref $rules->[0];

    $data = {
        request => 0,
        play => 0,
        adsense_request => 0,
        adsense_match_request => 0,
        adsense_click => 0,
        adsense_income => 0,
        %{$data // {}}, 
    };

    for my $rule (@$rules) {
        return undef unless ref $rule eq 'ARRAY' and @$rule == 2;
        my ($cond, $msg) = @$rule;

    }
}

sub var_dump {
    say Dumper(shift); 
}

sub microtime {
    return Time::HiRes::time();
}

sub is_null_datetime {
    my $datetime = shift;

    return !!(!$datetime or $datetime ~~ /^0000\D00\D00/);
}

sub check_script_singleton {
    open my $lock, '<', $0 or die "Couldn't open self: $!";

    flock $lock, LOCK_EX | LOCK_NB or die "This script is already running";

    return $lock;
}
1;
