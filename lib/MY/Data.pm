#
#===============================================================================
#
#         FILE: Data.pm
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Baboo (8boo.net), baboo.wg@gmail.com
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 2013/01/08 15时57分17秒
#     REVISION: ---
#===============================================================================

package MY::Data;

use MY::Utils;
use Mojo::Util qw/md5_sum encode decode/;
use Encode qw/encode_utf8/;
use Modern::Perl;
use M::Ad qw/:status/;
use M::Group;
use JSON::XS;
use utf8;

sub write {
    my ($type, $id, $content, $subdir) = @_;

    return 0 unless $ENV{ENGINE_DATA_DIRECTORY};
   
    my $dir = $ENV{ENGINE_DATA_DIRECTORY} . "/$type";

    mkdir $dir unless -r $dir;
    
    if ($subdir) {
        my $subdir = substr($id, 0, 2);

        $dir .= "/$subdir";

        mkdir $dir unless -r $dir;
    }

    my $file = "$dir/$id.json"; 

    if (-e $file) {
        my $new_md5 = md5_sum(encode_utf8($content));

        open my $fh, '<:utf8', $file;
        my $origin_content = do { local $/ = <$fh> };
        my $origin_md5 = md5_sum(encode_utf8($origin_content));
        close $fh;

        return 2 if $new_md5 eq $origin_md5;
    }

    open my $fh, '>:utf8', $file;

    print $fh $content;

    close $fh;

    return 1;
}

sub _get_slot_ads {
    my ($slot_id, $table) = @_;

    my @ads = M('ad')->select_hashref_rows({
        -bool => "find_in_set('$slot_id', $table.slot_id)",
        'me.status' => $M::Ad::STATUS_OK_FOR_ENGINE, 
    }, {
        select => "me.*,$table.*",
        left_join => [ $table, { id => 'id' } ],
    });
    
    return @ads;
}

sub _get_slot_brand_ads {
    return _get_slot_ads(shift, 'ad_brand');
}

sub _get_slot_pop_ads {
    return _get_slot_ads(shift, 'ad_pop');
}

sub build_slot_brand_ad_filter {
    my ($slot_id, $serialize_in_json) = @_;

    my @ads = _get_slot_brand_ads($slot_id);  

    return build_slot_ad_filter($slot_id, \@ads, $serialize_in_json);
}

sub build_slot_pop_ad_filter {
    my ($slot_id, $serialize_in_json) = @_;

    my @ads = _get_slot_pop_ads($slot_id);  

    return build_slot_ad_filter($slot_id, \@ads, $serialize_in_json);
}

sub build_slot_ad_filter {
    my ($slot_id, $ads, $serialize_in_json) = @_;

    my @filter = ();

    my $count = 1;
    for my $ad (@$ads) {
        
        my $conds = [];
        my $id = $ad->{id};

               
        if ($ad->{start_time} && !is_null_datetime($ad->{start_time})) {
            push @$conds, [ 'time', '>=', $ad->{start_time} ];
        }

        if ($ad->{end_time} && !is_null_datetime($ad->{end_time})) {
            push @$conds, [ 'time', '<=', $ad->{end_time} ];
        }

        my %limit = (
            total_pv_limit => 'request',
            daily_pv_limit => 'd_request',
            total_click_limit => 'click',
            daily_click_limit => 'd_click',
            total_pop_limit => 'aclick',
            daily_pop_limit => 'd_aclick',
        );

        for my $limit (keys %limit) {
            if ($ad->{$limit}) {
                push @$conds, [ $limit{$limit} . '.' . $id, '<', $ad->{$limit} ];
            }
        }
             
        if ($ad->{pv_group_id}) {
            if (my $group = M::Group->singleton->get($ad->{pv_group_id})) {

                M::Group::extend_config($group);
                my $gid = 'g' . $group->{id};
                for my $limit (keys %limit) {
                    if ($group->{$limit}) {
                        push @$conds, [ $limit{$limit} . '.' . $gid, '<', $group->{$limit} ];
                    }
                }

                if ($group->{frequency}) {
                    $ad->{frequency} = $group->{frequency};
                    $ad->{frequency_id} = $gid;
                }
            }
        }

        if ($ad->{frequency}) {
            my $fid = $ad->{frequency_id} || $id;
            push @$conds, [ "f.$fid", '<', $ad->{frequency} ];
        }

        eval {
            my $data = $ad->{config} ? my_decode_json($ad->{config}) : {};
            push @$conds, @{$data->{_cond} || []};
        };

        unless (@$conds) {
            push @$conds, [ 'time', '>=', '0000-00-00' ];
        }

        # 均匀投放，初期简单的将pv限制打散在每个小时里
        if ($ad->{evenly}) {
            my $delivery_hours = _get_delivery_hours($conds);
            
            if ($ad->{daily_pv_limit} && $delivery_hours) {
                my $hour_pv_limit = int($ad->{daily_pv_limit} / $delivery_hours);

                push @$conds, [ 'h_request' . '.' . $id, '<', $hour_pv_limit ];
            }

            if ($ad->{daily_pop_limit} && $delivery_hours) {
                my $hour_pop_limit = int($ad->{daily_pop_limit} / $delivery_hours);

                push @$conds, [ 'h_aclick' . '.' . $id, '<', $hour_pop_limit ];

            }
        }

        my $result = { id => $id, weight => $ad->{weight}, evenly => $ad->{evenly} };
        
        if ($ad->{material_ids}) {
            my @mids = split /,/, $ad->{material_ids};
            $result->{mids} = \@mids;
        }

        push @$conds, [ 'result.' . ($count++), '=',  $result];

        push @filter, $conds;
    }

    if ($serialize_in_json) {
        return decode('UTF-8', encode_json(\@filter));
    }

    return \@filter;
}

sub _get_delivery_hours
{
    my ($conds) = @_;
    
    for my $cond (@$conds) {
        if ($cond->[0] eq 'hour') {
            my @list = map { $_ ~~ /^([^.]+)\.\.([^.]+)$/ ? $1..$2 : $_ } split(/,/, $cond->[2], -1);    
            if (@list) {
                return scalar(@list);
            }
        }
    }

    return 24;
}
1;
