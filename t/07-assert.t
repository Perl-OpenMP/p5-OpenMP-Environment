use strict;
use warnings;

use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};
use Test::More;

use OpenMP::Environment qw/:assert/;
use OpenMP::Environment::Constants ();

my %valid = (
    OMP_CANCELLATION        => q{true},
    OMP_DISPLAY_ENV         => q{verbose},
    OMP_DEFAULT_DEVICE      => 0,
    OMP_NUM_TEAMS           => 2,
    OMP_DYNAMIC             => q{true},
    OMP_MAX_ACTIVE_LEVELS   => 2,
    OMP_MAX_TASK_PRIORITY   => 0,
    OMP_NESTED              => q{true},
    OMP_NUM_THREADS         => q{8,4,2},
    OMP_PROC_BIND           => q{MASTER,CLOSE,SPREAD},
    OMP_PLACES              => q{{0,1},{2,3}},
    OMP_STACKSIZE           => q{64M},
    OMP_SCHEDULE            => q{nonmonotonic:dynamic,4},
    OMP_TARGET_OFFLOAD      => q{default},
    OMP_THREAD_LIMIT        => 64,
    OMP_WAIT_POLICY         => q{passive},
    GOMP_CPU_AFFINITY       => q{0 3 1-2 4-15:2},
    GOMP_DEBUG              => 1,
    GOMP_STACKSIZE          => q{1024G},
    GOMP_SPINCOUNT          => q{INFINITY},
    GOMP_RTEMS_THREAD_POOLS => q{1@WRK0:3$4@WRK1},
    OMP_TEAMS_THREAD_LIMIT  => 32,
    OMP_ALLOCATOR           => q{omp_low_lat_mem_space:pinned=true,partition=nearest},
    OMP_AFFINITY_FORMAT     => q{thread %n affinity %A},
    OMP_DISPLAY_AFFINITY    => q{false},
);

for my $ev ( OpenMP::Environment::Constants::environment_names() ) {
    local $ENV{$ev} = $valid{$ev};
    ok assert($ev), qq{assert dispatch validates $ev};
}

{
    local $ENV{OMP_CANCELLATION} = q{true};
    ok assert(omp_cancellation), q{assert accepts a constant value};
    is $ENV{OMP_CANCELLATION}, q{TRUE}, q{assert preserves legacy uppercase normalization};
}

{
    local $ENV{OMP_NUM_THREADS};
    delete $ENV{OMP_NUM_THREADS};
    ok assert(omp_num_threads), q{assert considers an unset supported variable valid};
}

{
    local $ENV{GOMP_SPINCOUNT} = q{not sure about this one};
    my $ok = eval { assert(gomp_spincount); 1 };
    ok !$ok, q{assert strictly validates a historically pass-through variable};
    like $@, qr/GOMP_SPINCOUNT/, q{strict assertion names the invalid variable};
}

{
    local $ENV{OMP_NESTED} = q{FALSE};
    local $ENV{OMP_MAX_ACTIVE_LEVELS} = 4;
    my $nested_ok = eval { assert(omp_nested); 1 };
    ok !$nested_ok, q{assert detects the OMP_NESTED/OMP_MAX_ACTIVE_LEVELS conflict};
    like $@, qr/implementation-defined/, q{cross-variable assertion identifies implementation-defined behavior};

    my $levels_ok = eval { assert(omp_max_active_levels); 1 };
    ok !$levels_ok, q{either variable can surface the cross-variable conflict};
}

my $unknown_ok = eval { assert(q{OMP_NOT_REAL}); 1 };
ok !$unknown_ok, q{assert rejects an unknown environment variable};
like $@, qr/Unsupported OpenMP\/libgomp/, q{unknown assert explains the supported namespace};

{
    package OpenMPEnvironmentAssertOnly;
    use OpenMP::Environment qw/:assert/;
}
ok( OpenMPEnvironmentAssertOnly->can(q{assert}), q{:assert exports assert} );
ok( OpenMPEnvironmentAssertOnly->can(q{omp_schedule}), q{:assert exports constants} );
ok( !OpenMPEnvironmentAssertOnly->can(q{unset}), q{:assert does not export unset} );

{
    package OpenMPEnvironmentDSL;
    use OpenMP::Environment qw/:dsl/;
}
ok( OpenMPEnvironmentDSL->can(q{assert}), q{:dsl exports assert} );
ok( OpenMPEnvironmentDSL->can(q{unset}), q{:dsl exports unset} );
ok( OpenMPEnvironmentDSL->can(q{omp_target_offload}), q{:dsl exports constants} );

{
    local %ENV = %ENV;
    @ENV{ keys %valid } = values %valid;
    my $env = OpenMP::Environment->new;
    ok $env->assert_omp_environment, q{legacy assert_omp_environment uses the strict validation engine};
}

{
    local $ENV{OMP_SCHEDULE} = q{banana};
    my $env = OpenMP::Environment->new;
    my $ok = eval { $env->assert_omp_environment; 1 };
    ok !$ok, q{legacy assert_omp_environment now detects malformed formerly-pass-through syntax};
    like $@, qr/OMP_SCHEDULE/, q{strict environment assertion reports the malformed variable};
}

done_testing;
