package MY::FormHelper;
use Mojo::Base -strict;  
use Exporter qw/import/;
use Text::Xslate;

our @EXPORT = qw/selected checked form_select form_radio/;

sub selected {
    my ($name, $value, $default_value) = @_;
    
    $default_value = Text::Xslate->current_vars->{c}->param($name) || $default_value;

    return $default_value ~~ $value ? ' selected="selected"' : '';
}

sub checked {
    my ($name, $value, $default_value) = @_;

    $default_value = Text::Xslate->current_vars->{c}->param($name) || $default_value;

    return $default_value ~~ $value ? ' checked="checked"' : '';
}

sub form_select {
    my ($name, $options, $default_value, $attrs) = @_;

    $attrs //= '';

    my $html = qq(<select name="$name" $attrs>);
    
    for my $option (@$options) {
        my $selected = selected($name, $option->{value}, $default_value);
        my $value = $option->{value} // '';
        $html .= qq(
        <option value="$value" $selected>$option->{name}</option>
        );
    }
    
    $html .= '</select>';

    return $html;
}

sub form_radio {
    my ($name, $options, $default_value, $attrs, $label_attrs) = @_;

    $attrs //= '';
    $label_attrs //= '';

    $options = [ $options ] unless ref $options eq 'ARRAY';

    my $html = '';

    for my $option (@$options) {
        my $checked = checked($name, $option->{value}, $default_value);
        $html .= qq(
        <label $label_attrs><input type="radio" name="$name" value="$option->{value}" $checked $attrs/> $option->{name} </label>&nbsp;&nbsp; 
        );
    }

    return $html;
}

1;
