package Package::Prototype::_Mode;
use strict;
use warnings;

sub checks {
    my ($args) = @_;
    my $options = ref($args->[0]) eq 'HASH' ? shift @$args : {};
    die "Unknown check option" if grep { $_ ne 'mode' } keys %$options;
    my $mode = exists $options->{mode} ? $options->{mode} : 'syntax';
    die "Expected mode checked or syntax"
        unless defined($mode) && !ref($mode) && ($mode eq 'checked' || $mode eq 'syntax');
    my $runtime = $mode eq 'checked';
    return ($runtime, $runtime || $^C);
}

1;
