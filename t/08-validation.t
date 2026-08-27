use strict;
use warnings;

use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};
use Test::More;

use OpenMP::Environment::Validation qw/
    validate_value validate_assignment assert_variable assert_environment
    analyze_environment validation_rules
/;

sub rejects {
    my ( $name, $value, $label, $pattern ) = @_;
    local $@;
    eval { validate_value( $name, $value ) };
    ok length($@), $label;
    like $@, $pattern || qr/\Q$name\E/, qq{$label reports a useful diagnostic};
}

my $rules = validation_rules();
is scalar( @{ $rules->{fields} } ), 25, q{validation metadata contains every supported field};
is scalar( keys %{ $rules->{validators} } ), 25, q{validation metadata contains every validator};
ok grep( { $_ eq q{OMP_CANCELLATION} } @{ $rules->{normalized} } ), q{validation metadata records legacy-normalized variables};
ok grep( { $_ eq q{OMP_NUM_THREADS} } @{ $rules->{assignment_validated} } ), q{validation metadata records variables validated during compatible assignment};
is_deeply $rules->{whitespace_significant}, [ q{OMP_AFFINITY_FORMAT} ], q{validation metadata identifies the OpenMP whitespace-significant exception};
is $rules->{profile}, q{OpenMP 5.2 + GCC 16.2/libgomp}, q{validation metadata names the selected standards/runtime profile};

local $@;
eval { validate_value( undef, 1 ) };
like $@, qr/name is required/, q{validate_value requires a variable name};
eval { validate_value( q{OMP_NOT_REAL}, 1 ) };
like $@, qr/Unsupported/, q{validate_value rejects unsupported names};
is validate_value( q{OMP_NUM_THREADS}, undef ), undef, q{validate_value passes undef through};

is validate_assignment( q{GOMP_SPINCOUNT}, q{historical pass through} ), q{historical pass through}, q{assignment compatibility keeps formerly unvalidated values pass-through};
is validate_assignment( q{OMP_CANCELLATION}, q{true} ), q{TRUE}, q{assignment validation retains legacy normalization};
eval { validate_assignment( undef, 1 ) };
like $@, qr/name is required/, q{validate_assignment requires a variable name};
eval { validate_assignment( q{OMP_NOT_REAL}, 1 ) };
like $@, qr/Unsupported/, q{validate_assignment rejects unsupported names};
is validate_assignment( q{GOMP_SPINCOUNT}, undef ), undef, q{validate_assignment passes undef through};

is validate_value( q{OMP_CANCELLATION}, q{true} ), q{TRUE}, q{OMP_CANCELLATION accepts true};
is validate_value( q{OMP_CANCELLATION}, q{  true  } ), q{TRUE}, q{OMP_CANCELLATION accepts OpenMP-permitted surrounding whitespace};
rejects( q{OMP_CANCELLATION}, q{sometimes}, q{OMP_CANCELLATION rejects unknown boolean}, qr/TRUE/ );
is validate_value( q{OMP_DISPLAY_ENV}, q{verbose} ), q{VERBOSE}, q{OMP_DISPLAY_ENV accepts VERBOSE};
rejects( q{OMP_DISPLAY_ENV}, q{ALL}, q{OMP_DISPLAY_ENV rejects unknown display level} );
is validate_value( q{OMP_DEFAULT_DEVICE}, 0 ), 0, q{OMP_DEFAULT_DEVICE accepts zero};
is validate_value( q{OMP_DEFAULT_DEVICE}, q{  0  } ), q{0}, q{OMP_DEFAULT_DEVICE ignores surrounding OpenMP whitespace in strict validation};
rejects( q{OMP_DEFAULT_DEVICE}, -1, q{OMP_DEFAULT_DEVICE rejects negative values}, qr/integer/ );
rejects( q{OMP_DEFAULT_DEVICE}, q{gpu0}, q{OMP_DEFAULT_DEVICE rejects non-integers}, qr/integer/ );
is validate_value( q{OMP_NUM_TEAMS}, 1 ), 1, q{OMP_NUM_TEAMS accepts a positive integer};
rejects( q{OMP_NUM_TEAMS}, 0, q{OMP_NUM_TEAMS rejects zero} );
is validate_value( q{OMP_DYNAMIC}, q{true} ), q{true}, q{OMP_DYNAMIC accepts true without changing historical case};
is validate_value( q{OMP_DYNAMIC}, 1 ), 1, q{OMP_DYNAMIC retains historical numeric true support};
rejects( q{OMP_DYNAMIC}, q{maybe}, q{OMP_DYNAMIC rejects non-boolean value} );
is validate_value( q{OMP_MAX_ACTIVE_LEVELS}, 1 ), 1, q{OMP_MAX_ACTIVE_LEVELS follows libgomp positive-integer rule};
rejects( q{OMP_MAX_ACTIVE_LEVELS}, 0, q{OMP_MAX_ACTIVE_LEVELS applies the documented libgomp/legacy positive-integer profile even though OpenMP 5.2 permits zero} );
is validate_value( q{OMP_MAX_TASK_PRIORITY}, 0 ), 0, q{OMP_MAX_TASK_PRIORITY accepts zero};
rejects( q{OMP_MAX_TASK_PRIORITY}, -1, q{OMP_MAX_TASK_PRIORITY rejects negative values} );
is validate_value( q{OMP_NESTED}, q{true} ), q{TRUE}, q{OMP_NESTED retains uppercase filter};
is validate_value( q{OMP_NESTED}, 0 ), 0, q{OMP_NESTED retains numeric false compatibility};
rejects( q{OMP_NESTED}, q{maybe}, q{OMP_NESTED rejects non-boolean value} );
is validate_value( q{OMP_NUM_THREADS}, q{8, 4, 2} ), q{8, 4, 2}, q{OMP_NUM_THREADS accepts nested positive-integer lists};
rejects( q{OMP_NUM_THREADS}, q{8,0,2}, q{OMP_NUM_THREADS rejects zero in a list}, qr/comma-separated/ );

for my $value ( q{TRUE}, q{FALSE}, q{PRIMARY}, q{CLOSE}, q{SPREAD}, q{MASTER,CLOSE,SPREAD}, q{spread,close,primary} ) {
    is validate_value( q{OMP_PROC_BIND}, $value ), $value, qq{OMP_PROC_BIND accepts $value};
}
rejects( q{OMP_PROC_BIND}, q{TRUE,CLOSE}, q{OMP_PROC_BIND does not mix boolean and policy-list syntax} );
rejects( q{OMP_PROC_BIND}, q{NEAR}, q{OMP_PROC_BIND rejects an unknown policy} );

for my $value (
    q{cores}, q{cores(4)}, q{vendor_places(2)}, q{{0,1,2},{3,4,5}},
    q{{0:4},{4:4}}, q{!{0},1:3}, q{{0}:4:2}, q{0:4:2}
) {
    is validate_value( q{OMP_PLACES}, $value ), $value, qq{OMP_PLACES accepts $value};
}
rejects( q{OMP_PLACES}, q{}, q{OMP_PLACES rejects an empty value} );
rejects( q{OMP_PLACES}, q{{0,,2}}, q{OMP_PLACES rejects an empty resource} );
rejects( q{OMP_PLACES}, q{{0,2},}, q{OMP_PLACES rejects an empty place} );
rejects( q{OMP_PLACES}, '{0,2}, {3', q{OMP_PLACES rejects unbalanced braces} );
rejects( q{OMP_PLACES}, q{{x}}, q{OMP_PLACES rejects a nonnumeric explicit resource} );
is validate_value( q{OMP_PLACES}, q{{!0,1}} ), q{{!0,1}}, q{OMP_PLACES accepts resource exclusion syntax};
rejects( q{OMP_PLACES}, q{@}, q{OMP_PLACES rejects a malformed explicit place} );
rejects( q{OMP_PLACES}, '0}', q{OMP_PLACES rejects an unmatched closing brace} );
rejects( q{OMP_PLACES}, q{{}}, q{OMP_PLACES rejects an empty explicit resource list} );
rejects( q{OMP_PLACES}, q{0:0}, q{OMP_PLACES rejects a zero-length place interval} );

for my $value ( q{1}, q{1024}, q{64M}, q{2G}, q{4096K} ) {
    is validate_value( q{OMP_STACKSIZE}, $value ), $value, qq{OMP_STACKSIZE accepts $value};
}
rejects( q{OMP_STACKSIZE}, q{0}, q{OMP_STACKSIZE rejects zero} );
rejects( q{OMP_STACKSIZE}, q{4T}, q{OMP_STACKSIZE rejects an unsupported unit} );

for my $value ( q{static}, q{dynamic,4}, q{guided,8}, q{auto}, q{monotonic:static}, q{nonmonotonic:dynamic,4} ) {
    is validate_value( q{OMP_SCHEDULE}, $value ), $value, qq{OMP_SCHEDULE accepts $value};
}
rejects( q{OMP_SCHEDULE}, q{banana}, q{OMP_SCHEDULE rejects an unknown kind} );
rejects( q{OMP_SCHEDULE}, q{dynamic,0}, q{OMP_SCHEDULE rejects zero chunk size} );
rejects( q{OMP_SCHEDULE}, q{random:dynamic,4}, q{OMP_SCHEDULE rejects an unknown modifier} );
is validate_value( q{OMP_SCHEDULE}, q{  dynamic,4  } ), q{dynamic,4}, q{OMP_SCHEDULE ignores surrounding OpenMP whitespace};

is validate_value( q{OMP_TARGET_OFFLOAD}, q{mandatory} ), q{MANDATORY}, q{OMP_TARGET_OFFLOAD normalizes a standard value};
rejects( q{OMP_TARGET_OFFLOAD}, q{FORCE}, q{OMP_TARGET_OFFLOAD rejects an unknown mode} );
is validate_value( q{OMP_THREAD_LIMIT}, 1 ), 1, q{OMP_THREAD_LIMIT accepts positive integer};
rejects( q{OMP_THREAD_LIMIT}, 0, q{OMP_THREAD_LIMIT rejects zero} );
is validate_value( q{OMP_WAIT_POLICY}, q{active} ), q{ACTIVE}, q{OMP_WAIT_POLICY accepts ACTIVE};
rejects( q{OMP_WAIT_POLICY}, q{SLEEP}, q{OMP_WAIT_POLICY rejects unknown policy} );

for my $value ( q{0}, q{0 3 1-2 4-15:2}, q{0,2,4-8:2} ) {
    is validate_value( q{GOMP_CPU_AFFINITY}, $value ), $value, qq{GOMP_CPU_AFFINITY accepts $value};
}
rejects( q{GOMP_CPU_AFFINITY}, q{cpu0}, q{GOMP_CPU_AFFINITY rejects symbolic CPUs} );
rejects( q{GOMP_CPU_AFFINITY}, q{4-8:0}, q{GOMP_CPU_AFFINITY rejects zero stride} );
is validate_value( q{GOMP_DEBUG}, 0 ), 0, q{GOMP_DEBUG accepts zero};
is validate_value( q{GOMP_DEBUG}, 1 ), 1, q{GOMP_DEBUG accepts one};
rejects( q{GOMP_DEBUG}, 2, q{GOMP_DEBUG rejects values outside 0/1} );
is validate_value( q{GOMP_STACKSIZE}, q{1024} ), q{1024}, q{GOMP_STACKSIZE accepts the GNU-native numeric-kilobyte form};
is validate_value( q{GOMP_STACKSIZE}, q{1024G} ), q{1024G}, q{GOMP_STACKSIZE retains the documented OpenMP::Environment unit-suffix compatibility extension};
is validate_assignment( q{GOMP_STACKSIZE}, q{1024G} ), q{1024G}, q{GOMP_STACKSIZE assignment remains pass-through for pre-1.5 compatibility};
rejects( q{GOMP_STACKSIZE}, 0, q{GOMP_STACKSIZE rejects zero} );
for my $value ( q{0}, q{300000}, q{4k}, q{30M}, q{2G}, q{1T}, q{INFINITE}, q{INFINITY} ) {
    is validate_value( q{GOMP_SPINCOUNT}, $value ), $value, qq{GOMP_SPINCOUNT accepts $value};
}
rejects( q{GOMP_SPINCOUNT}, q{4m}, q{GOMP_SPINCOUNT preserves documented suffix case} );
rejects( q{GOMP_SPINCOUNT}, q{forever}, q{GOMP_SPINCOUNT rejects unknown words} );
is validate_value( q{GOMP_RTEMS_THREAD_POOLS}, q{1@WRK0:3$4@WRK1} ), q{1@WRK0:3$4@WRK1}, q{GOMP_RTEMS_THREAD_POOLS accepts libgomp example grammar};
rejects( q{GOMP_RTEMS_THREAD_POOLS}, q{0@WRK0}, q{GOMP_RTEMS_THREAD_POOLS rejects zero pool count} );
rejects( q{GOMP_RTEMS_THREAD_POOLS}, q{1WRK0}, q{GOMP_RTEMS_THREAD_POOLS requires scheduler separator} );
is validate_value( q{OMP_TEAMS_THREAD_LIMIT}, 1 ), 1, q{OMP_TEAMS_THREAD_LIMIT accepts positive integer};
rejects( q{OMP_TEAMS_THREAD_LIMIT}, 0, q{OMP_TEAMS_THREAD_LIMIT rejects zero} );

for my $value (
    q{omp_default_mem_alloc}, q{omp_high_bw_mem_alloc}, q{omp_default_mem_space},
    q{omp_large_cap_mem_space:alignment=16,pinned=true},
    q{omp_low_lat_mem_space:sync_hint=private,access=thread,pool_size=1024,partition=nearest},
    q{ompx_gnu_pinned_mem_alloc}, q{ompx_gnu_managed_mem_alloc},
    q{ompx_gnu_managed_mem_space}
) {
    is validate_value( q{OMP_ALLOCATOR}, $value ), $value, qq{OMP_ALLOCATOR accepts $value};
}
rejects( q{OMP_ALLOCATOR}, q{not_an_allocator}, q{OMP_ALLOCATOR rejects an unknown allocator} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:}, q{OMP_ALLOCATOR rejects an empty trait list} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:alignment=3}, q{OMP_ALLOCATOR requires power-of-two alignment} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:alignment=foo}, q{OMP_ALLOCATOR requires numeric alignment} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:pool_size=0}, q{OMP_ALLOCATOR requires positive pool size} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:pinned=maybe}, q{OMP_ALLOCATOR validates boolean traits} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:partition=random}, q{OMP_ALLOCATOR validates partition values} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:access=process}, q{OMP_ALLOCATOR validates access values} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:sync_hint=often}, q{OMP_ALLOCATOR validates sync_hint values} );
is validate_value( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:fallback=allocator_fb} ), q{omp_low_lat_mem_space:fallback=allocator_fb}, q{OMP_ALLOCATOR accepts allocator_fb because libgomp explicitly lists it as an allowed fallback token};
is validate_value( q{OMP_ALLOCATOR}, q{OMP_HIGH_BW_MEM_ALLOC} ), q{OMP_HIGH_BW_MEM_ALLOC}, q{OMP_ALLOCATOR values are case-insensitive under the general OpenMP environment rule};
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:fb_data=not_an_allocator}, q{OMP_ALLOCATOR validates fb_data allocator names before applying the libgomp restriction} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:fb_data=omp_default_mem_alloc}, q{OMP_ALLOCATOR rejects OpenMP fb_data because libgomp documents it as unsupported} );
is validate_value( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:fallback=default_mem_fb} ), q{omp_low_lat_mem_space:fallback=default_mem_fb}, q{OMP_ALLOCATOR accepts non-handle fallback choices};
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:alignment=16,alignment=32}, q{OMP_ALLOCATOR rejects duplicate traits} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:mystery=yes}, q{OMP_ALLOCATOR rejects unknown traits} );
rejects( q{OMP_ALLOCATOR}, q{omp_low_lat_mem_space:pinned}, q{OMP_ALLOCATOR rejects malformed traits} );

for my $value ( q{literal text}, q{thread %n affinity %A}, q{level %4L thread %0.2n}, q{host %.12{host}}, q{%% %n}, q{%{thread_num}}, q{vendor %x} ) {
    is validate_value( q{OMP_AFFINITY_FORMAT}, $value ), $value, qq{OMP_AFFINITY_FORMAT accepts $value};
}
is validate_value( q{OMP_AFFINITY_FORMAT}, q{  %n  } ), q{  %n  }, q{OMP_AFFINITY_FORMAT preserves significant leading and trailing whitespace};
rejects( q{OMP_AFFINITY_FORMAT}, q{thread %}, q{OMP_AFFINITY_FORMAT rejects a trailing percent} );
rejects( q{OMP_AFFINITY_FORMAT}, q{thread %0n}, q{OMP_AFFINITY_FORMAT rejects malformed width syntax} );
rejects( q{OMP_AFFINITY_FORMAT}, q{thread %.0L}, q{OMP_AFFINITY_FORMAT rejects a zero minimum width} );
rejects( q{OMP_AFFINITY_FORMAT}, q{thread %0.0L}, q{OMP_AFFINITY_FORMAT rejects a zero-padded zero minimum width} );
rejects( q{OMP_AFFINITY_FORMAT}, q{thread %{bad-name}}, q{OMP_AFFINITY_FORMAT rejects malformed long field name} );
is validate_value( q{OMP_DISPLAY_AFFINITY}, q{false} ), q{FALSE}, q{OMP_DISPLAY_AFFINITY accepts and normalizes false};
rejects( q{OMP_DISPLAY_AFFINITY}, q{sometimes}, q{OMP_DISPLAY_AFFINITY rejects non-boolean value} );

local $@;
eval { assert_variable( [], q{OMP_NUM_THREADS} ) };
like $@, qr/hash reference/, q{assert_variable requires a hash reference};
eval { assert_variable( {}, q{OMP_NOT_REAL} ) };
like $@, qr/Unsupported/, q{assert_variable rejects unknown names};
my %one = ( OMP_NUM_THREADS => q{4,2} );
ok assert_variable( \%one, q{OMP_NUM_THREADS} ), q{assert_variable validates a set variable};
my %unset;
ok assert_variable( \%unset, q{OMP_NUM_THREADS} ), q{assert_variable accepts an unset variable};
my %unrelated_conflict = ( OMP_NESTED => q{FALSE}, OMP_MAX_ACTIVE_LEVELS => 4, OMP_SCHEDULE => q{static} );
ok assert_variable( \%unrelated_conflict, q{OMP_SCHEDULE} ), q{assert_variable ignores a cross-variable conflict unrelated to the requested variable};

local $@;
eval { assert_environment([]) };
like $@, qr/hash reference/, q{assert_environment requires a hash reference};
my %strict = ( OMP_CANCELLATION => q{true}, OMP_SCHEDULE => q{guided,4} );
ok assert_environment( \%strict ), q{assert_environment validates a portable environment};
is $strict{OMP_CANCELLATION}, q{TRUE}, q{assert_environment writes normalized values back};
my %conflict = ( OMP_NESTED => q{FALSE}, OMP_MAX_ACTIVE_LEVELS => 4 );
eval { assert_environment( \%conflict ) };
like $@, qr/conflict/, q{assert_environment rejects an explicit OpenMP implementation-defined conflict};

local $@;
eval { analyze_environment([]) };
like $@, qr/hash reference/, q{analyze_environment requires a hash reference};
my %analysis_env = (
    OMP_NESTED            => q{TRUE},
    OMP_MAX_ACTIVE_LEVELS => 4,
    OMP_NUM_THREADS       => q{8,4},
    OMP_PROC_BIND         => q{SPREAD,CLOSE},
    GOMP_CPU_AFFINITY     => q{0-7},
    OMP_PLACES            => q{cores},
    OMP_DEFAULT_DEVICE    => 7,
    OMP_STACKSIZE         => q{64G},
    OMP_ALLOCATOR         => q{omp_high_bw_mem_alloc},
    OMP_THREAD_LIMIT      => 1024,
    GOMP_RTEMS_THREAD_POOLS => q{1@WRK0},
);
my $analysis = analyze_environment( \%analysis_env );
ok $analysis->{valid}, q{runtime-dependent but syntactically valid environment remains valid};
ok @{ $analysis->{runtime_dependent} } >= 8, q{analysis identifies runtime-dependent settings without probing the system};
ok grep( /OMP_PROC_BIND takes precedence/, @{ $analysis->{notes} } ), q{analysis documents GNU precedence relationship};
ok grep( /OMP_NESTED has no effect/, @{ $analysis->{notes} } ), q{analysis documents nonconflicting OMP_NESTED relationship};
ok grep( /max-active-levels-var/, @{ $analysis->{notes} } ), q{analysis documents nested list effect on max-active-levels-var};

my $bad_analysis = analyze_environment( { OMP_SCHEDULE => q{banana} } );
ok !$bad_analysis->{valid}, q{analysis marks malformed environment invalid};
is scalar( @{ $bad_analysis->{errors} } ), 1, q{analysis reports malformed value as an error};
my $conflict_analysis = analyze_environment( { OMP_NESTED => q{false}, OMP_MAX_ACTIVE_LEVELS => 2 } );
ok !$conflict_analysis->{valid}, q{analysis marks cross-variable conflict invalid};
is $conflict_analysis->{conflicts}->[0]->{class}, q{implementation-defined}, q{analysis classifies the OpenMP conflict};

done_testing;

