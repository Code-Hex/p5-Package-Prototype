use v5.16;
use warnings;
use Types::Standard qw(Dict Int Str);
use Package::Prototype::Typed { mode => 'always' },
    user_record => Dict[
        user_id      => Int,
        display_name => Str,
    ];

my $display_name = $ARGV[0];
my $user = user_record({
    user_id      => 42,
    display_name => $display_name,
});

print "$user->{user_id}: $user->{display_name}\n";
