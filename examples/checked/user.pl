use v5.16;
use warnings;
use Types::Standard qw(Dict Int Str);
use Package::Prototype::Checked
    checked_user => Dict[
        user_id      => Int,
        display_name => Str,
    ];

my $user = checked_user({
    user_id      => 42,
    display_name => $ARGV[0],
});

print "$user->{user_id}: $user->{display_name}\n";
