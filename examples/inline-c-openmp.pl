#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};

BEGIN {
  # set envar for num threads pre build/linking
  #
  $ENV{OMP_NUM_THREADS} = 16;
  #
  # build/link
  use Inline (
    C         => 'DATA',
    ccflags   => q{-fopenmp},
    libs      => q{-lgomp -lm}, #<-- also don't understand why I need to explicitly include libgomp
    name      => q{Test},

    #clean_after_build => 1,
    BUILD_NOISY       => 1,
  );
}

# F I R S T  C A L L
# when the envar here is set in BEGIN, before Inline::C does
# it's thing; the result will be (as expected):

test('fart');

#
# $ perl examples/inline-c-openmp.pl 
# 1616161616161616161616161616161616161616161616161616161616161616
#

# set up with different num omp threads
$ENV{OMP_NUM_THREADS} = 8;

# S E C O N D  C A L L
test('fart');
#
# Expected,
#
# $ perl examples/inline-c-openmp.pl 
# 88888888
#
# the result is the same as the first, giving the impression that
# the environment is baked in somehow
#
# Get:
#
# $ perl examples/inline-c-openmp.pl 
# 1616161616161616161616161616161616161616161616161616161616161616
#
# If I do nothing in the BEGIN block to affect OMP_NUM_THREADS, the
# default internal value of OMP_NUM_THREADS=4 (if not set otherwise)
# is "fixed"
#

__DATA__

__C__
#include <omp.h>
#include <stdlib.h>
#include <stdio.h>

void test(SV* sv_name) {
  #pragma omp parallel
  {
    printf("%d", omp_get_num_threads()); 
  }
}
