use strict;
use warnings;

use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};
use Test::More;

use OpenMP::Environment qw/:unset/;
use OpenMP::Environment::Constants ();

my @constant_names = OpenMP::Environment::Constants::constant_names();
my @environment_names = OpenMP::Environment::Constants::environment_names();

is scalar(@constant_names), 25, q{25 DSL constants are defined};
is scalar(@environment_names), 25, q{25 canonical environment names are defined};

for my $i ( 0 .. $#constant_names ) {
    my $constant = $constant_names[$i];
    my $ev = $environment_names[$i];
    my $code = __PACKAGE__->can($constant);
    ok $code, qq{$constant is imported by :unset};
    is $code->(), $ev, qq{$constant resolves to $ev};
    ok OpenMP::Environment::Constants::is_environment_name($ev), qq{$ev is recognized};

    local $ENV{$ev} = qq{value-$i};
    is unset($ev), qq{value-$i}, qq{unset dispatches $ev and returns old value};
    ok !exists $ENV{$ev}, qq{unset removes $ev};
}

ok !OpenMP::Environment::Constants::is_environment_name(q{OMP_NOT_REAL}), q{unsupported environment name is rejected by constants lookup};

my $unknown_ok = eval { unset(q{OMP_NOT_REAL}); 1 };
ok !$unknown_ok, q{unset rejects an unknown environment variable};
like $@, qr/Unsupported OpenMP\/libgomp/, q{unknown unset explains the supported namespace};

{
    package OpenMPEnvironmentNoImport;
    use OpenMP::Environment;
}
ok !OpenMPEnvironmentNoImport->can(q{unset}), q{unset is not exported by default};
ok !OpenMPEnvironmentNoImport->can(q{omp_num_threads}), q{DSL constants are not exported by default};

{
    package OpenMPEnvironmentUnsetOnly;
    use OpenMP::Environment qw/:unset/;
}
ok( OpenMPEnvironmentUnsetOnly->can(q{unset}), q{:unset exports unset} );
ok( OpenMPEnvironmentUnsetOnly->can(q{omp_num_threads}), q{:unset exports constants} );
ok( !OpenMPEnvironmentUnsetOnly->can(q{assert}), q{:unset does not export assert} );

{
    package OpenMPEnvironmentExplicitUnset;
    use OpenMP::Environment qw/unset omp_num_threads/;
}
ok( OpenMPEnvironmentExplicitUnset->can(q{unset}), q{explicit unset import works} );
is OpenMPEnvironmentExplicitUnset::omp_num_threads(), q{OMP_NUM_THREADS}, q{explicit constant import works};

my $bad_import = eval q{package OpenMPEnvironmentBadImport; use OpenMP::Environment qw/not_a_symbol/; 1;};
ok !$bad_import, q{unknown import is rejected};
like $@, qr/not exported/, q{unknown import reports export error};

local $ENV{OMP_NUM_THREADS} = 9;
is unset omp_num_threads, 9, q{literal unset omp_num_threads DSL form works};

my $env = OpenMP::Environment->new;
$env->omp_num_threads = 7;
is $env->unset_omp_num_threads, 7, q{legacy unset_omp_num_threads remains supported};
ok !exists $ENV{OMP_NUM_THREADS}, q{legacy unsetter still deletes the environment variable};

done_testing;

