use strict;
use warnings;

use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};

use OpenMP::Environment ();

my $env = OpenMP::Environment->new;

$env->print_summary_set;

for my $i ( qw/1 2 4 8 16 32 64 128/ ) { 
  $env->omp_num_threads($i);
  $env->print_summary_set;
}
