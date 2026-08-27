use strict;
use warnings;

use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};

use Test::More;
use OpenMP::Environment ();

local %ENV = %ENV;

my $env = OpenMP::Environment->new;

my @legacy_vars = qw/
    OMP_CANCELLATION OMP_DISPLAY_ENV OMP_DEFAULT_DEVICE OMP_NUM_TEAMS
    OMP_DYNAMIC OMP_MAX_ACTIVE_LEVELS OMP_MAX_TASK_PRIORITY OMP_NESTED
    OMP_NUM_THREADS OMP_PROC_BIND OMP_PLACES OMP_STACKSIZE OMP_SCHEDULE
    OMP_TARGET_OFFLOAD OMP_THREAD_LIMIT OMP_WAIT_POLICY GOMP_CPU_AFFINITY
    GOMP_DEBUG GOMP_STACKSIZE GOMP_SPINCOUNT GOMP_RTEMS_THREAD_POOLS
    OMP_TEAMS_THREAD_LIMIT
/;

my @new_vars = qw/OMP_ALLOCATOR OMP_AFFINITY_FORMAT OMP_DISPLAY_AFFINITY/;
my @vars = $env->vars;

is_deeply(
    \@vars,
    [ @legacy_vars, @new_vars ],
    q{legacy vars ordering is preserved and GCC 16.2 variables are appended},
);

# Keep the test independent of the environment in which it is run.
delete @ENV{@vars};

my @accessors = (
    [ omp_allocator             => unset_omp_allocator             => q{omp_high_bw_mem_alloc} ],
    [ omp_affinity_format       => unset_omp_affinity_format       => q{thread %n affinity %A} ],
    [ omp_cancellation          => unset_omp_cancellation          => q{TRUE} ],
    [ omp_display_affinity      => unset_omp_display_affinity      => q{TRUE} ],
    [ omp_display_env           => unset_omp_display_env           => q{VERBOSE} ],
    [ omp_default_device        => unset_omp_default_device        => 1 ],
    [ omp_dynamic               => unset_omp_dynamic               => q{true} ],
    [ omp_max_active_levels     => unset_omp_max_active_levels     => 2 ],
    [ omp_max_task_priority     => unset_omp_max_task_priority     => 1 ],
    [ omp_nested                => unset_omp_nested                => q{TRUE} ],
    [ omp_num_teams             => unset_omp_num_teams             => 2 ],
    [ omp_num_threads           => unset_omp_num_threads           => q{8,4,2} ],
    [ omp_proc_bind             => unset_omp_proc_bind             => q{CLOSE} ],
    [ omp_places                => unset_omp_places                => q{cores} ],
    [ omp_stacksize             => unset_omp_stacksize             => q{64M} ],
    [ omp_schedule              => unset_omp_schedule              => q{dynamic,4} ],
    [ omp_target_offload        => unset_omp_target_offload        => q{DEFAULT} ],
    [ omp_teams_thread_limit    => unset_omp_teams_thread_limit    => 2 ],
    [ omp_thread_limit          => unset_omp_thread_limit          => 8 ],
    [ omp_wait_policy           => unset_omp_wait_policy           => q{PASSIVE} ],
    [ gomp_cpu_affinity         => unset_gomp_cpu_affinity         => q{0-7} ],
    [ gomp_debug                => unset_gomp_debug                => 1 ],
    [ gomp_stacksize            => unset_gomp_stacksize            => 65536 ],
    [ gomp_spincount            => unset_gomp_spincount            => q{300000} ],
    [ gomp_rtems_thread_pools   => unset_gomp_rtems_thread_pools   => q{1@WRK0} ],
);

for my $case (@accessors) {
    my ( $getter_setter, $unsetter, $value ) = @$case;

    is(
        $env->$getter_setter($value),
        $value,
        qq{$getter_setter sets and returns a value},
    );
    is(
        $env->$getter_setter(),
        $value,
        qq{$getter_setter gets the current value},
    );
    is(
        $env->$unsetter(),
        $value,
        qq{$unsetter returns the deleted value},
    );
    is(
        $env->$getter_setter(),
        undef,
        qq{$getter_setter returns undef after unset},
    );
}

# Exercise each compatibility path in the special boolean accessors.
is $env->omp_dynamic(q{true}), q{true}, q{OMP_DYNAMIC true path};
is $env->omp_dynamic(q{false}), q{true}, q{OMP_DYNAMIC false string unsets and returns old value};
is $env->omp_dynamic(q{TRUE}), q{TRUE}, q{OMP_DYNAMIC uppercase true path};
is $env->omp_dynamic(q{FALSE}), q{TRUE}, q{OMP_DYNAMIC uppercase false unsets and returns old value};
is $env->omp_dynamic(q{1}), q{1}, q{OMP_DYNAMIC numeric true path};
is $env->omp_dynamic(q{0}), q{1}, q{OMP_DYNAMIC numeric false unsets and returns old value};

is $env->omp_nested(q{true}), q{TRUE}, q{OMP_NESTED true path};
is $env->omp_nested(q{false}), q{TRUE}, q{OMP_NESTED false string unsets and returns old value};
is $env->omp_nested(q{TRUE}), q{TRUE}, q{OMP_NESTED uppercase true path};
is $env->omp_nested(q{FALSE}), q{TRUE}, q{OMP_NESTED uppercase false unsets and returns old value};
is $env->omp_nested(q{1}), q{1}, q{OMP_NESTED numeric true path};
is $env->omp_nested(q{0}), q{1}, q{OMP_NESTED numeric false unsets and returns old value};

# Direct validator coverage, including both sides of the short-circuit checks.
is OpenMP::Environment::_is_ge_if_set( 1, undef ), undef, q{integer validator accepts undef};
like OpenMP::Environment::_is_ge_if_set( 1, q{x} ), qr/integer/, q{integer validator rejects non-digits};
like OpenMP::Environment::_is_ge_if_set( 1, 0 ), qr/integer/, q{integer validator rejects a digit below the minimum};
is OpenMP::Environment::_is_ge_if_set( 1, 1 ), undef, q{integer validator accepts the minimum};

is OpenMP::Environment::_is_positive_integer_list_if_set(undef), undef, q{thread-list validator accepts undef};
is OpenMP::Environment::_is_positive_integer_list_if_set(q{8, 4, 2}), undef, q{thread-list validator accepts a positive integer list};
like OpenMP::Environment::_is_positive_integer_list_if_set(q{8,0,2}), qr/comma-separated/, q{thread-list validator rejects zero};

my $null_validator = OpenMP::Environment::_no_validate();
is ref($null_validator), q{CODE}, q{null validator factory returns a coderef};
is $null_validator->(q{anything}), undef, q{null validator accepts arbitrary input};

# Summary branches when nothing is set.
delete @ENV{@vars};
is scalar($env->vars_set), 0, q{vars_set is empty when nothing is set};
is scalar($env->vars_unset), scalar(@vars), q{vars_unset contains every supported variable when nothing is set};
ok $env->assert_omp_environment, q{empty OpenMP environment validates};

my $stdout = q{};
{
    open my $capture, q{>}, \$stdout or die qq{open scalar handle: $!};
    local *STDOUT = $capture;
    my $summary = $env->_omp_summary_set;
    like $summary, qr/Summary of OpenMP Environmental SET/, q{set summary returns its heading};
}
like $stdout, qr/- none/, q{set summary prints the none marker when no supported variables are set};

$stdout = q{};
{
    open my $capture, q{>}, \$stdout or die qq{open scalar handle: $!};
    local *STDOUT = $capture;
    my $summary = $env->_omp_summary_unset;
    like $summary, qr/OMP_CANCELLATION/, q{unset summary includes supported variables};
}
unlike $stdout, qr/- none/, q{unset summary does not print none while variables are unset};

like $env->_omp_summary, qr/<XXunsetXX>/, q{all-variable summary marks unset values};

# Summary branches when everything is set. Direct assignment is deliberate: the
# summary helpers report environment state and should not require revalidation.
my %truthy_value = (
    OMP_CANCELLATION        => q{TRUE},
    OMP_DISPLAY_ENV         => q{TRUE},
    OMP_DEFAULT_DEVICE      => 1,
    OMP_NUM_TEAMS           => 1,
    OMP_DYNAMIC             => q{true},
    OMP_MAX_ACTIVE_LEVELS   => 1,
    OMP_MAX_TASK_PRIORITY   => 1,
    OMP_NESTED              => q{TRUE},
    OMP_NUM_THREADS         => 1,
    OMP_PROC_BIND           => q{CLOSE},
    OMP_PLACES              => q{cores},
    OMP_STACKSIZE           => q{64M},
    OMP_SCHEDULE            => q{static},
    OMP_TARGET_OFFLOAD      => q{DEFAULT},
    OMP_THREAD_LIMIT        => 1,
    OMP_WAIT_POLICY         => q{PASSIVE},
    GOMP_CPU_AFFINITY       => q{0-7},
    GOMP_DEBUG              => 1,
    GOMP_STACKSIZE          => 65536,
    GOMP_SPINCOUNT          => 300000,
    GOMP_RTEMS_THREAD_POOLS => q{1@WRK0},
    OMP_TEAMS_THREAD_LIMIT  => 1,
    OMP_ALLOCATOR           => q{omp_default_mem_alloc},
    OMP_AFFINITY_FORMAT     => q{thread %n affinity %A},
    OMP_DISPLAY_AFFINITY    => q{TRUE},
);

for my $var ( keys %truthy_value ) {
    $ENV{$var} = $truthy_value{$var};
}
is scalar($env->vars_unset), 0, q{vars_unset is empty when everything is set};
is scalar($env->vars_set), scalar(@vars), q{vars_set contains every supported variable when everything is set};
ok $env->assert_omp_environment, q{fully populated valid OpenMP environment validates};

$stdout = q{};
{
    open my $capture, q{>}, \$stdout or die qq{open scalar handle: $!};
    local *STDOUT = $capture;
    my $summary = $env->_omp_summary_unset;
    like $summary, qr/Summary of OpenMP Environmental UNSET/, q{unset summary returns its heading};
}
like $stdout, qr/- none/, q{unset summary prints none when everything is set};

$stdout = q{};
{
    open my $capture, q{>}, \$stdout or die qq{open scalar handle: $!};
    local *STDOUT = $capture;
    my $summary = $env->_omp_summary_set;
    like $summary, qr/OMP_ALLOCATOR/, q{set summary includes new GCC 16.2 variables};
}
unlike $stdout, qr/- none/, q{set summary does not print none when variables are set};

like $env->_omp_summary, qr/OMP_DISPLAY_AFFINITY\s+TRUE/, q{all-variable summary shows new values};

# Exercise all three public print wrappers while capturing their output.
$stdout = q{};
{
    open my $capture, q{>}, \$stdout or die qq{open scalar handle: $!};
    local *STDOUT = $capture;
    ok $env->print_omp_summary_set, q{print_omp_summary_set returns a true print result};
    ok $env->print_omp_summary_unset, q{print_omp_summary_unset returns a true print result};
    ok $env->print_omp_summary, q{print_omp_summary returns a true print result};
}
like $stdout, qr/Summary of OpenMP Environmental ALL/, q{public summary methods print to STDOUT};

# Cover the error path and filtered-value return path explicitly.
my $ok = eval { $env->_assert_valid( q{OMP_DISPLAY_AFFINITY}, q{true} ) };
is $ok, q{TRUE}, q{_assert_valid returns the filtered value};
my $died = !eval { $env->_assert_valid( q{OMP_DISPLAY_AFFINITY}, q{invalid} ); 1 };
ok $died, q{_assert_valid dies on validation failure};

# Finish with the environment clean so later tests are not influenced.
delete @ENV{@vars};

done_testing;

