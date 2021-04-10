#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};

use OpenMP::Environment ();

my $env = OpenMP::Environment->new;

for my $i ( qw/1 2 4 8 16 32 64 128/ ) { 
  $env->omp_num_threads($i);
  #<< add `system` call to OpenMP compiled executable >>
  # e.g.,
  my $exit_code = system($ARGV[0]);
  #
  if ($exit_code == 0) {
    print qq{OK\n}
  }
  else {
    print qq{OOPS\n};
    exit $exit_code;
  }
}

exit;
