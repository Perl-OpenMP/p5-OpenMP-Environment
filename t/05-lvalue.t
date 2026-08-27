use strict;
use warnings;

use Test::More;
use OpenMP::Environment;

my $env = OpenMP::Environment->new;
my @vars = $env->vars;
delete @ENV{@vars};

my @lvalue_cases = (
    [ omp_allocator           => unset_omp_allocator           => OMP_ALLOCATOR           => q{omp_high_bw_mem_alloc}   => q{omp_high_bw_mem_alloc} ],
    [ omp_affinity_format     => unset_omp_affinity_format     => OMP_AFFINITY_FORMAT     => q{thread %n affinity %A}   => q{thread %n affinity %A} ],
    [ omp_cancellation        => unset_omp_cancellation        => OMP_CANCELLATION        => q{true}                    => q{TRUE} ],
    [ omp_display_affinity    => unset_omp_display_affinity    => OMP_DISPLAY_AFFINITY    => q{true}                    => q{TRUE} ],
    [ omp_display_env         => unset_omp_display_env         => OMP_DISPLAY_ENV         => q{verbose}                 => q{VERBOSE} ],
    [ omp_default_device      => unset_omp_default_device      => OMP_DEFAULT_DEVICE      => 0                          => 0 ],
    [ omp_dynamic             => unset_omp_dynamic             => OMP_DYNAMIC             => q{true}                    => q{true} ],
    [ omp_max_active_levels   => unset_omp_max_active_levels   => OMP_MAX_ACTIVE_LEVELS   => 2                          => 2 ],
    [ omp_max_task_priority   => unset_omp_max_task_priority   => OMP_MAX_TASK_PRIORITY   => 0                          => 0 ],
    [ omp_nested              => unset_omp_nested              => OMP_NESTED              => q{true}                    => q{TRUE} ],
    [ omp_num_threads         => unset_omp_num_threads         => OMP_NUM_THREADS         => q{8,4,2}                   => q{8,4,2} ],
    [ omp_num_teams           => unset_omp_num_teams           => OMP_NUM_TEAMS           => 2                          => 2 ],
    [ omp_proc_bind           => unset_omp_proc_bind           => OMP_PROC_BIND           => q{spread}                  => q{spread} ],
    [ omp_places              => unset_omp_places              => OMP_PLACES              => q{cores}                   => q{cores} ],
    [ omp_stacksize           => unset_omp_stacksize           => OMP_STACKSIZE           => q{64M}                     => q{64M} ],
    [ omp_schedule            => unset_omp_schedule            => OMP_SCHEDULE            => q{dynamic,4}               => q{dynamic,4} ],
    [ omp_target_offload      => unset_omp_target_offload      => OMP_TARGET_OFFLOAD      => q{default}                 => q{DEFAULT} ],
    [ omp_thread_limit        => unset_omp_thread_limit        => OMP_THREAD_LIMIT        => 8                          => 8 ],
    [ omp_teams_thread_limit  => unset_omp_teams_thread_limit  => OMP_TEAMS_THREAD_LIMIT  => 4                          => 4 ],
    [ omp_wait_policy         => unset_omp_wait_policy         => OMP_WAIT_POLICY         => q{passive}                 => q{PASSIVE} ],
    [ gomp_cpu_affinity       => unset_gomp_cpu_affinity       => GOMP_CPU_AFFINITY       => q{0-7}                     => q{0-7} ],
    [ gomp_debug              => unset_gomp_debug              => GOMP_DEBUG              => 1                          => 1 ],
    [ gomp_stacksize          => unset_gomp_stacksize          => GOMP_STACKSIZE          => q{65536}                   => q{65536} ],
    [ gomp_spincount          => unset_gomp_spincount          => GOMP_SPINCOUNT          => q{300000}                  => q{300000} ],
    [ gomp_rtems_thread_pools => unset_gomp_rtems_thread_pools => GOMP_RTEMS_THREAD_POOLS => q{1@WRK0}                  => q{1@WRK0} ],
);

for my $case (@lvalue_cases) {
    my ( $accessor, $unsetter, $variable, $input, $expected ) = @$case;

    $env->$accessor = $input;

    is $ENV{$variable}, $expected, qq{$accessor lvalue assignment updates $variable};
    is $env->$accessor, $expected, qq{$accessor remains a getter after lvalue assignment};
    is $env->$unsetter(), $expected, qq{$unsetter still removes lvalue-assigned $variable};
}

# Compound lvalue operations must route their STORE back through validation.
$env->omp_num_threads = 3;
$env->omp_num_threads++;
is $ENV{OMP_NUM_THREADS}, 4, q{post-increment works through a validated lvalue};

$env->gomp_spincount = 100;
$env->gomp_spincount += 50;
is $ENV{GOMP_SPINCOUNT}, 150, q{numeric compound assignment works through an lvalue};

$env->omp_affinity_format = q{thread};
$env->omp_affinity_format .= q{ %n};
is $ENV{OMP_AFFINITY_FORMAT}, q{thread %n}, q{string compound assignment works through an lvalue};

# A failed lvalue STORE must not replace a previously valid environment value.
$env->omp_num_threads = 4;
my $ok = eval { $env->omp_num_threads = q{invalid}; 1 };
ok !$ok, q{invalid lvalue assignment dies};
like $@, qr/OMP_NUM_THREADS/, q{invalid lvalue assignment reports the variable};
is $ENV{OMP_NUM_THREADS}, 4, q{invalid lvalue assignment preserves the previous value};

# Preserve the historical false-value-means-unset behavior through lvalues.
$env->omp_dynamic = q{true};
$env->omp_dynamic = 0;
ok !exists $ENV{OMP_DYNAMIC}, q{OMP_DYNAMIC lvalue false value retains historical unset behavior};

$env->omp_nested = q{true};
$env->omp_nested = q{false};
ok !exists $ENV{OMP_NESTED}, q{OMP_NESTED lvalue false value retains historical unset behavior};

# Traditional call-style setters remain fully supported alongside lvalues.
is $env->omp_num_threads(6), 6, q{traditional setter syntax remains supported};
is $env->omp_num_threads(), 6, q{traditional getter syntax remains supported};
is $env->unset_omp_num_threads(), 6, q{traditional unsetter syntax remains supported};

# Explicit undef retains the established getter/no-op behavior for ordinary
# accessors; callers should continue to use the explicit unsetter to delete.
$env->omp_num_threads = 8;
$env->omp_num_threads = undef;
is $ENV{OMP_NUM_THREADS}, 8, q{undef lvalue assignment retains ordinary accessor compatibility semantics};
$env->unset_omp_num_threads;

delete @ENV{@vars};

done_testing;

