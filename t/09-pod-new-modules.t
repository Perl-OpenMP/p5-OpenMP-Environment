use strict;
use warnings;

use FindBin qw/$Bin/;
use Test::More;
use Pod::Simple::Checker;

for my $file ( qw/Constants.pm Validation.pm/ ) {
    my $path = qq{$Bin/../lib/OpenMP/Environment/$file};
    my $checker = Pod::Simple::Checker->new;
    $checker->output_string(\my $output);
    $checker->parse_file($path);
    ok !$checker->any_errata_seen, qq{OpenMP::Environment::$file POD parses without errors};
}

done_testing;

