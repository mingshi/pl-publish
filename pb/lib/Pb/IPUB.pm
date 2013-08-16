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

    $self->plugin('DefaultHelper');
    $self->plugin('Permission');
    $self->plugin('DataVersion');
    
    my $config = $self->plugin('Config', { file => 'config.conf' });
    return $config || {};
    return 1;
}
