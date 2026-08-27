use strict;
use warnings;

use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};
use Test::More;

use OpenMP::Environment;
use OpenMP::Environment::Validation qw/
    validate_value validate_assignment assert_variable assert_environment
    analyze_environment
/;

# Exercise each explicit-import arm independently.  This complements the
# public DSL tests without changing the regression files from master.
{
    package OpenMPEnvironmentExplicitAssert;
    use OpenMP::Environment qw/assert/;
}
package main;
ok( OpenMPEnvironmentExplicitAssert->can(q{assert}), q{explicit assert import is covered} );
ok( !OpenMPEnvironmentExplicitAssert->can(q{unset}), q{explicit assert import does not imply unset} );

{
    package OpenMPEnvironmentExplicitConstant;
    use OpenMP::Environment qw/omp_num_threads/;
}
package main;
is OpenMPEnvironmentExplicitConstant::omp_num_threads(), q{OMP_NUM_THREADS}, q{explicit constant-only import is covered};
ok( !OpenMPEnvironmentExplicitConstant->can(q{assert}), q{constant-only import does not imply assert} );
ok( !OpenMPEnvironmentExplicitConstant->can(q{unset}), q{constant-only import does not imply unset} );

# Retained private compatibility helper: cover both sides of each legacy
# predicate independently.
is OpenMP::Environment::_is_ge_if_set( 1, q{x} ),
  q{Value must be an integer great than or equal to 1},
  q{legacy integer helper rejects non-integers};
is OpenMP::Environment::_is_ge_if_set( 1, 0 ),
  q{Value must be an integer great than or equal to 1},
  q{legacy integer helper rejects values below the minimum};
is OpenMP::Environment::_is_ge_if_set( 1, 1 ), undef,
  q{legacy integer helper accepts the minimum};

# OpenMP 5.2 generally permits leading/trailing whitespace in environment
# values.  The public boolean compatibility behavior should still unset false
# values after that standard whitespace is ignored.
my $whitespace_env = OpenMP::Environment->new;
$whitespace_env->omp_dynamic(q{true});
$whitespace_env->omp_dynamic(q{  false  });
ok !exists $ENV{OMP_DYNAMIC},
  q{OMP_DYNAMIC whitespace-wrapped FALSE retains historical unset behavior};
$whitespace_env->omp_nested(q{true});
$whitespace_env->omp_nested(q{  FALSE  });
ok !exists $ENV{OMP_NESTED},
  q{OMP_NESTED whitespace-wrapped FALSE retains historical unset behavior};

# Assignment validation: exercise the strict legacy-validated failure path.
local $@;
eval { validate_assignment( q{OMP_CANCELLATION}, q{maybe} ) };
like $@, qr/OMP_CANCELLATION/, q{strict assignment path can fail for historically validated variables};

# assert_variable/assert_environment both distinguish absent values from keys
# that exist but are undef.
my %undefined_one = ( OMP_NUM_THREADS => undef );
ok assert_variable( \%undefined_one, q{OMP_NUM_THREADS} ),
  q{assert_variable accepts an explicitly undefined supported value};

my %undefined_environment = (
    OMP_NUM_THREADS => undef,
    OMP_SCHEDULE    => q{static},
);
ok assert_environment( \%undefined_environment ),
  q{assert_environment skips explicitly undefined supported values};

# Cover each stage of the portable OMP_NESTED / OMP_MAX_ACTIVE_LEVELS
# relationship without any system probing.
my $a = analyze_environment( { OMP_NESTED => q{FALSE} } );
ok $a->{valid}, q{FALSE OMP_NESTED alone is valid};

$a = analyze_environment({
    OMP_NESTED            => q{FALSE},
    OMP_MAX_ACTIVE_LEVELS => q{bogus},
});
ok !$a->{valid}, q{nonnumeric max-active-levels is a value error rather than a cross-variable conflict};
is scalar( @{ $a->{conflicts} } ), 0,
  q{nonnumeric max-active-levels does not enter numeric conflict logic};

$a = analyze_environment({
    OMP_NESTED            => q{FALSE},
    OMP_MAX_ACTIVE_LEVELS => 1,
});
ok $a->{valid}, q{FALSE OMP_NESTED with one active level is not the implementation-defined conflict};
is scalar( @{ $a->{conflicts} } ), 0,
  q{one active level leaves the conflict list empty};

$a = analyze_environment({
    OMP_NESTED            => q{FALSE},
    OMP_MAX_ACTIVE_LEVELS => 2,
});
ok !$a->{valid}, q{FALSE OMP_NESTED with more than one active level is flagged};
is scalar( @{ $a->{conflicts} } ), 1,
  q{the implementation-defined combination produces one conflict};

# Precedence/nesting notes: cover the partial and alternate paths separately.
$a = analyze_environment({ GOMP_CPU_AFFINITY => q{0-3} });
ok $a->{valid}, q{GOMP_CPU_AFFINITY alone is valid};
is scalar( @{ $a->{notes} } ), 0,
  q{GNU affinity precedence note requires OMP_PROC_BIND too};

$a = analyze_environment({ OMP_NESTED => q{TRUE} });
ok $a->{valid}, q{OMP_NESTED alone is valid};
is scalar( @{ $a->{notes} } ), 0,
  q{OMP_NESTED relationship note requires OMP_MAX_ACTIVE_LEVELS too};

$a = analyze_environment({
    OMP_NUM_THREADS => 8,
    OMP_PROC_BIND   => q{SPREAD,CLOSE},
});
ok $a->{valid}, q{PROC_BIND list with scalar NUM_THREADS is valid};
ok grep( /max-active-levels-var/, @{ $a->{notes} } ),
  q{PROC_BIND list independently triggers the nested-level initialization note};

$a = analyze_environment({
    OMP_NUM_THREADS => 8,
    OMP_PROC_BIND   => q{CLOSE},
});
ok $a->{valid}, q{single-item thread and binding settings are valid};
is scalar( @{ $a->{notes} } ), 0,
  q{single-item values do not trigger the nested-list note};

# OMP_PLACES parser edges exercise parenthesis state, top-level separator
# behavior, explicit place suffixes, and resource strides.
for my $bad (
    q{vendor(1,2)},
    q{vendor(1,2},
    q{vendor(1,2))},
) {
    local $@;
    eval { validate_value( q{OMP_PLACES}, $bad ) };
    like $@, qr/OMP_PLACES|Expected an explicit/, qq{OMP_PLACES rejects malformed parenthesized form $bad};
}

is validate_value( q{OMP_PLACES}, q{0:4:-1} ), q{0:4:-1},
  q{OMP_PLACES accepts a signed explicit-place stride};
is validate_value( q{OMP_PLACES}, q{{0:4:-1}} ), q{{0:4:-1}},
  q{OMP_PLACES accepts a signed resource stride};


# Public OMP_PLACES parsing rejects unbalanced input before the lower-level
# place helper is reached; call the helper directly to cover its defensive
# unbalanced-brace return and the matching-brace end-of-input path.
is OpenMP::Environment::Validation::_validate_place_interval(q[{0]),
  q{Unbalanced braces in OMP_PLACES},
  q{place-interval helper reports an unbalanced opening brace};
is OpenMP::Environment::Validation::_matching_brace(q[{0]), -1,
  q{matching-brace helper reports end-of-input without a close};

# A colon-bearing unknown memory-space name reaches the second half of the
# allocator name/space decision rather than the no-colon form.
local $@;
eval { validate_value( q{OMP_ALLOCATOR}, q{not_a_space:alignment=16} ) };
like $@, qr/predefined OpenMP allocator or memory space/,
  q{OMP_ALLOCATOR rejects an unknown colon-qualified memory space};

# Cover width syntax on the long affinity field form.
is validate_value( q{OMP_AFFINITY_FORMAT}, q{thread %.3{thread_num}} ),
  q{thread %.3{thread_num}},
  q{OMP_AFFINITY_FORMAT accepts width syntax on a long field};

# Direct helper coverage for the defined/no-comma/comma cases used by
# analyze_environment.  These are internal policy helpers, not system probes.
is OpenMP::Environment::Validation::_has_multiple_items(undef), 0,
  q{multiple-item helper handles undef};
is OpenMP::Environment::Validation::_has_multiple_items(q{8}), 0,
  q{multiple-item helper handles a scalar value};
is OpenMP::Environment::Validation::_has_multiple_items(q{8,4}), 1,
  q{multiple-item helper recognizes a list};
is OpenMP::Environment::Validation::_has_proc_bind_list(undef), 0,
  q{proc-bind list helper handles undef};
is OpenMP::Environment::Validation::_has_proc_bind_list(q{CLOSE}), 0,
  q{proc-bind list helper handles one policy};
is OpenMP::Environment::Validation::_has_proc_bind_list(q{CLOSE,SPREAD}), 1,
  q{proc-bind list helper recognizes multiple policies};

# The enum helper has both successful and rejected paths and is used by many
# public validators.
is OpenMP::Environment::Validation::_enum( q{TRUE}, qw/TRUE FALSE/ ), undef,
  q{enum helper recognizes an allowed value};
like OpenMP::Environment::Validation::_enum( q{MAYBE}, qw/TRUE FALSE/ ),
  qr/Expected one of/,
  q{enum helper reports a rejected value};

done_testing;

