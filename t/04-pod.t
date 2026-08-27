use strict;
use warnings;

use FindBin qw/$Bin/;
use Test::More tests => 1;
use Pod::Simple::Checker;

my $file = qq{$Bin/../lib/OpenMP/Environment.pm};
my $checker = Pod::Simple::Checker->new;
$checker->output_string(\my $output);
$checker->parse_file($file);

ok !$checker->any_errata_seen, q{OpenMP::Environment POD parses without errors};

