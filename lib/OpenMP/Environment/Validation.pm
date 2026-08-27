package OpenMP::Environment::Validation;
use strict;
use warnings;

use Carp qw/croak/;
use Exporter qw/import/;
use OpenMP::Environment::Constants ();

our $VERSION = q{1.5.0};
our @EXPORT_OK = qw/validate_value validate_assignment assert_variable assert_environment analyze_environment validation_rules/;

my %UPPERCASE_FILTER = map { $_ => 1 } qw/
  OMP_CANCELLATION OMP_NESTED OMP_DISPLAY_AFFINITY OMP_DISPLAY_ENV
  OMP_TARGET_OFFLOAD OMP_WAIT_POLICY
/;


my %LEGACY_VALIDATED = map { $_ => 1 } qw/
  OMP_CANCELLATION OMP_DISPLAY_AFFINITY OMP_DISPLAY_ENV OMP_DEFAULT_DEVICE
  OMP_DYNAMIC OMP_MAX_ACTIVE_LEVELS OMP_MAX_TASK_PRIORITY OMP_NESTED
  OMP_NUM_TEAMS OMP_NUM_THREADS OMP_TARGET_OFFLOAD OMP_TEAMS_THREAD_LIMIT
  OMP_THREAD_LIMIT OMP_WAIT_POLICY GOMP_DEBUG
/;
my %VALIDATOR = (
    OMP_CANCELLATION        => \&_validate_omp_cancellation,
    OMP_DISPLAY_ENV         => \&_validate_omp_display_env,
    OMP_DEFAULT_DEVICE      => \&_validate_omp_default_device,
    OMP_NUM_TEAMS           => \&_validate_omp_num_teams,
    OMP_DYNAMIC             => \&_validate_omp_dynamic,
    OMP_MAX_ACTIVE_LEVELS   => \&_validate_omp_max_active_levels,
    OMP_MAX_TASK_PRIORITY   => \&_validate_omp_max_task_priority,
    OMP_NESTED              => \&_validate_omp_nested,
    OMP_NUM_THREADS         => \&_validate_omp_num_threads,
    OMP_PROC_BIND           => \&_validate_omp_proc_bind,
    OMP_PLACES              => \&_validate_omp_places,
    OMP_STACKSIZE           => \&_validate_omp_stacksize,
    OMP_SCHEDULE            => \&_validate_omp_schedule,
    OMP_TARGET_OFFLOAD      => \&_validate_omp_target_offload,
    OMP_THREAD_LIMIT        => \&_validate_omp_thread_limit,
    OMP_WAIT_POLICY         => \&_validate_omp_wait_policy,
    GOMP_CPU_AFFINITY       => \&_validate_gomp_cpu_affinity,
    GOMP_DEBUG              => \&_validate_gomp_debug,
    GOMP_STACKSIZE          => \&_validate_gomp_stacksize,
    GOMP_SPINCOUNT          => \&_validate_gomp_spincount,
    GOMP_RTEMS_THREAD_POOLS => \&_validate_gomp_rtems_thread_pools,
    OMP_TEAMS_THREAD_LIMIT  => \&_validate_omp_teams_thread_limit,
    OMP_ALLOCATOR           => \&_validate_omp_allocator,
    OMP_AFFINITY_FORMAT     => \&_validate_omp_affinity_format,
    OMP_DISPLAY_AFFINITY    => \&_validate_omp_display_affinity,
);

sub validation_rules {
    return {
        fields                 => [ OpenMP::Environment::Constants::environment_names() ],
        normalized             => [ sort keys %UPPERCASE_FILTER ],
        assignment_validated   => [ sort keys %LEGACY_VALIDATED ],
        whitespace_significant => [ q{OMP_AFFINITY_FORMAT} ],
        validators             => { %VALIDATOR },
        profile                => q{OpenMP 5.2 + GCC 16.2/libgomp},
    };
}

sub validate_value {
    my ( $name, $value ) = @_;
    croak q{Environment variable name is required} if not defined $name;
    croak qq{Unsupported OpenMP/libgomp environment variable "$name"}
      if not OpenMP::Environment::Constants::is_environment_name($name);
    return undef if not defined $value;

    my $normalized = $value;

    # OpenMP 5.2 Chapter 21 states that OpenMP environment-variable values are
    # generally case-insensitive and may contain leading/trailing whitespace.
    # OMP_AFFINITY_FORMAT is the explicit exception: it is case-sensitive and
    # leading/trailing whitespace is significant (Section 21.2.5).  Preserve
    # that format string byte-for-byte; trim the other OMP_* values before
    # applying the module's established case normalization.
    if ( $name =~ m/\AOMP_/ and $name ne q{OMP_AFFINITY_FORMAT} ) {
        $normalized = _trim($normalized);
    }
    $normalized = uc($normalized) if $UPPERCASE_FILTER{$name};
    my $validator = $VALIDATOR{$name};
    my $error = $validator->($normalized);
    die qq{(fatal) $name="$value": $error\n\n} if defined $error;
    return $normalized;
}

sub validate_assignment {
    my ( $name, $value ) = @_;
    croak q{Environment variable name is required} if not defined $name;
    croak qq{Unsupported OpenMP/libgomp environment variable "$name"}
      if not OpenMP::Environment::Constants::is_environment_name($name);
    return undef if not defined $value;

    # Assignment semantics are intentionally backward-compatible.  Variables
    # that were historically pass-through remain pass-through; the stricter
    # grammar is available through assert()/assert_omp_environment and this
    # module's validate_value() API.
    return $value if not $LEGACY_VALIDATED{$name};
    return validate_value( $name, $value );
}

sub assert_variable {
    my ( $env, $name ) = @_;
    croak q{Environment hash reference is required} if ref($env) ne q{HASH};
    croak qq{Unsupported OpenMP/libgomp environment variable "$name"}
      if not OpenMP::Environment::Constants::is_environment_name($name);

    if ( exists $env->{$name} ) {
        if ( defined $env->{$name} ) {
            $env->{$name} = validate_value( $name, $env->{$name} );
        }
    }

    my $analysis = analyze_environment($env);
    foreach my $conflict ( @{ $analysis->{conflicts} } ) {
        next if not grep { $_ eq $name } @{ $conflict->{variables} };
        die qq{(fatal) OpenMP environment conflict: $conflict->{message}\n};
    }
    return 1;
}

sub assert_environment {
    my ($env) = @_;
    croak q{Environment hash reference is required} if ref($env) ne q{HASH};

    foreach my $name ( OpenMP::Environment::Constants::environment_names() ) {
        next if not exists $env->{$name};
        next if not defined $env->{$name};
        $env->{$name} = validate_value( $name, $env->{$name} );
    }

    my $analysis = analyze_environment($env);
    if ( @{ $analysis->{conflicts} } ) {
        my $message = join q{; }, map { $_->{message} } @{ $analysis->{conflicts} };
        die qq{(fatal) OpenMP environment conflict: $message\n};
    }
    return 1;
}

sub analyze_environment {
    my ($env) = @_;
    croak q{Environment hash reference is required} if ref($env) ne q{HASH};

    my @errors;
    foreach my $name ( OpenMP::Environment::Constants::environment_names() ) {
        next if not exists $env->{$name};
        next if not defined $env->{$name};
        my $ok = eval { validate_value( $name, $env->{$name} ); 1 };
        push @errors, { variable => $name, message => $@ } if not $ok;
    }

    my @conflicts;
    if ( _is_false( $env->{OMP_NESTED} ) ) {
        if ( defined $env->{OMP_MAX_ACTIVE_LEVELS} ) {
            if ( $env->{OMP_MAX_ACTIVE_LEVELS} =~ m/\A\d+\z/ ) {
                if ( $env->{OMP_MAX_ACTIVE_LEVELS} > 1 ) {
                    push @conflicts, {
                        variables => [qw/OMP_NESTED OMP_MAX_ACTIVE_LEVELS/],
                        class     => q{implementation-defined},
                        message   => q{OMP_NESTED=FALSE with OMP_MAX_ACTIVE_LEVELS greater than 1 is implementation-defined by OpenMP 5.2},
                    };
                }
            }
        }
    }

    my @runtime_dependent;
    _runtime_note( \@runtime_dependent, $env, q{OMP_PLACES}, q{processor numbering, abstract-place mapping, and resource availability are implementation/runtime dependent} );
    _runtime_note( \@runtime_dependent, $env, q{OMP_DEFAULT_DEVICE}, q{the requested device number is not checked for existence} );
    _runtime_note( \@runtime_dependent, $env, q{OMP_STACKSIZE}, q{the requested stack size is not checked against available runtime resources} );
    _runtime_note( \@runtime_dependent, $env, q{OMP_ALLOCATOR}, q{memory-space and allocator availability are not probed} );
    _runtime_note( \@runtime_dependent, $env, q{OMP_THREAD_LIMIT}, q{the implementation-supported thread limit is not probed} );
    _runtime_note( \@runtime_dependent, $env, q{OMP_MAX_ACTIVE_LEVELS}, q{the implementation-supported active-level limit is not probed} );
    _runtime_note( \@runtime_dependent, $env, q{OMP_NUM_THREADS}, q{the implementation-supported thread count is not probed} );
    _runtime_note( \@runtime_dependent, $env, q{GOMP_CPU_AFFINITY}, q{CPU identifiers are syntax-checked but are not checked against the host} );
    _runtime_note( \@runtime_dependent, $env, q{GOMP_RTEMS_THREAD_POOLS}, q{RTEMS scheduler names and priorities are syntax-checked but not queried from RTEMS} );

    my @notes;
    if ( exists $env->{GOMP_CPU_AFFINITY} ) {
        if ( exists $env->{OMP_PROC_BIND} ) {
            push @notes, q{OMP_PROC_BIND takes precedence over GOMP_CPU_AFFINITY in GNU libgomp when both are set};
        }
    }
    if ( exists $env->{OMP_NESTED} ) {
        if ( exists $env->{OMP_MAX_ACTIVE_LEVELS} ) {
            my $conflicting = 0;
            if ( _is_false( $env->{OMP_NESTED} ) ) {
                if ( $env->{OMP_MAX_ACTIVE_LEVELS} =~ m/\A\d+\z/ ) {
                    $conflicting = 1 if $env->{OMP_MAX_ACTIVE_LEVELS} > 1;
                }
            }
            push @notes, q{when OMP_NESTED and OMP_MAX_ACTIVE_LEVELS are both set without the conflicting FALSE/>1 combination, OMP_NESTED has no effect}
              if not $conflicting;
        }
    }
    if ( _has_multiple_items( $env->{OMP_NUM_THREADS} ) ) {
        push @notes, q{multi-item OMP_NUM_THREADS or OMP_PROC_BIND values participate in initialization of max-active-levels-var unless overridden by stronger nesting controls};
    }
    elsif ( _has_proc_bind_list( $env->{OMP_PROC_BIND} ) ) {
        push @notes, q{multi-item OMP_NUM_THREADS or OMP_PROC_BIND values participate in initialization of max-active-levels-var unless overridden by stronger nesting controls};
    }

    my $valid = 1;
    $valid = 0 if @errors;
    $valid = 0 if @conflicts;
    return {
        valid             => $valid,
        errors            => \@errors,
        conflicts         => \@conflicts,
        runtime_dependent => \@runtime_dependent,
        notes             => \@notes,
    };
}

sub _runtime_note {
    my ( $notes, $env, $name, $message ) = @_;
    return if not exists $env->{$name};
    push @$notes, { variable => $name, message => $message };
    return;
}

sub _is_false {
    my ($value) = @_;
    return 0 if not defined $value;
    return 1 if $value =~ m/\A(?:0|false)\z/i;
    return 0;
}

sub _has_multiple_items {
    my ($value) = @_;
    return 0 if not defined $value;
    return 1 if $value =~ /,/;
    return 0;
}

sub _has_proc_bind_list {
    my ($value) = @_;
    return 0 if not defined $value;
    return 1 if $value =~ /,/;
    return 0;
}

sub _enum {
    my ( $value, @allowed ) = @_;
    my %allowed = map { uc($_) => 1 } @allowed;
    return undef if $allowed{ uc $value };
    return q{Expected one of: } . join( q{, }, @allowed );
}

sub _integer_at_least {
    my ( $value, $minimum ) = @_;
    return q{Value must be an integer} if $value !~ m/\A\d+\z/;
    return qq{Value must be an integer greater than or equal to $minimum} if $value < $minimum;
    return;
}

sub _positive_integer_list {
    my ($value) = @_;
    return if $value =~ m/\A\s*[1-9]\d*(?:\s*,\s*[1-9]\d*)*\s*\z/;
    return q{Value must be a comma-separated list of positive integers};
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fCANCELLATION.html
# OpenMP 5.2: Section 21.2.6, OMP_CANCELLATION.
# OpenMP requires TRUE/FALSE; other values make behavior implementation-defined.
# libgomp implements the standard boolean values. We validate syntax only and
# do not inspect whether cancellation points will actually be encountered.
sub _validate_omp_cancellation { return _enum( shift, qw/TRUE FALSE/ ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fDISPLAY_005fENV.html
# OpenMP 5.2: Section 21.7, OMP_DISPLAY_ENV.
# OpenMP defines TRUE, FALSE, and VERBOSE. libgomp uses VERBOSE to include GNU
# implementation-specific variables. We validate the portable values only.
sub _validate_omp_display_env { return _enum( shift, qw/TRUE FALSE VERBOSE/ ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fDEFAULT_005fDEVICE.html
# OpenMP 5.2: Section 21.2.7, OMP_DEFAULT_DEVICE.
# The grammar is a non-negative integer. Device existence/availability is a
# runtime property and is deliberately not checked by this portable module.
sub _validate_omp_default_device { return _integer_at_least( shift, 0 ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fNUM_005fTEAMS.html
# OpenMP 5.2: Section 21.6.1, OMP_NUM_TEAMS.
# The value is a positive integer. Whether that many teams can be created is a
# runtime/target matter and is deliberately not probed.
sub _validate_omp_num_teams { return _integer_at_least( shift, 1 ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fDYNAMIC.html
# OpenMP 5.2: Section 21.1.1, OMP_DYNAMIC.
# OpenMP specifies TRUE/FALSE and leaves other values implementation-defined.
# For compatibility with historical OpenMP::Environment behavior, 1/0 are also
# accepted; the public accessor retains its established false-value-unsets rule.
sub _validate_omp_dynamic { return _enum( shift, qw/TRUE FALSE 1 0/ ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fMAX_005fACTIVE_005fLEVELS.html
# OpenMP 5.2: Section 21.1.4, OMP_MAX_ACTIVE_LEVELS.
# OpenMP permits a non-negative integer, but GCC/libgomp documents a positive
# integer and the pre-1.5.0 module rejected zero. We follow libgomp and preserve
# that compatibility. The supported maximum is system/runtime dependent and is
# not queried here.
sub _validate_omp_max_active_levels { return _integer_at_least( shift, 1 ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fMAX_005fTASK_005fPRIORITY.html
# OpenMP 5.2: Section 21.2.9, OMP_MAX_TASK_PRIORITY.
# The portable grammar is a non-negative integer. Runtime priority support is
# not probed.
sub _validate_omp_max_task_priority { return _integer_at_least( shift, 0 ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fNESTED.html
# OpenMP 5.2: Section 21.1.5, OMP_NESTED (deprecated).
# TRUE/FALSE are defined; other values are implementation-defined. OpenMP also
# declares FALSE together with OMP_MAX_ACTIVE_LEVELS>1 implementation-defined;
# that relationship is checked by analyze_environment/assert_environment.
# 1/0 remain accepted for backward compatibility with this module.
sub _validate_omp_nested { return _enum( shift, qw/TRUE FALSE 1 0/ ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fNUM_005fTHREADS.html
# OpenMP 5.2: Section 21.1.2, OMP_NUM_THREADS.
# OpenMP permits a comma-separated list of positive integers for nested levels.
# Values above runtime capability are implementation-defined and are not
# system-checked. Multiple items also influence max-active-levels-var.
sub _validate_omp_num_threads { return _positive_integer_list(shift) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fPROC_005fBIND.html
# OpenMP 5.2: Section 21.1.7, OMP_PROC_BIND.
# OpenMP accepts TRUE, FALSE, or a list of PRIMARY/CLOSE/SPREAD. MASTER is
# deprecated by OpenMP but libgomp explicitly continues to accept it, so this
# validator accepts MASTER as a GNU/backward-compatible spelling. Placement and
# the policy selected by TRUE are implementation/runtime dependent and not probed.
sub _validate_omp_proc_bind {
    my ($value) = @_;
    return if $value =~ m/\A\s*(?:TRUE|FALSE)\s*\z/i;
    return if $value =~ m/\A\s*(?:PRIMARY|MASTER|CLOSE|SPREAD)(?:\s*,\s*(?:PRIMARY|MASTER|CLOSE|SPREAD))*\s*\z/i;
    return q{Expected TRUE, FALSE, or a comma-separated list of PRIMARY, MASTER, CLOSE, or SPREAD};
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fPLACES.html
# OpenMP 5.2: Section 21.1.6, OMP_PLACES.
# OpenMP defines abstract names, explicit resource lists, intervals, strides,
# and exclusions, while explicitly leaving processor numbering, abstract-name
# meaning, resource mapping, and additional abstract names implementation-defined.
# libgomp documents THREADS/CORES/SOCKETS/LL_CACHES/NUMA_DOMAINS and the standard
# explicit syntax. We validate grammar, including implementation-defined abstract
# identifiers, but never verify that a referenced processor/resource exists.
sub _validate_omp_places {
    my ($value) = @_;
    my $text = _trim($value);
    return q{OMP_PLACES must not be empty} if $text eq q{};
    return if $text =~ m/\A[A-Za-z_][A-Za-z0-9_]*(?:\(\s*[1-9]\d*\s*\))?\z/;

    my @items = _split_top_level( $text, q{,} );
    return q{Malformed OMP_PLACES list} if not @items;
    foreach my $item (@items) {
        my $err = _validate_place_interval($item);
        return $err if defined $err;
    }
    return;
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fSTACKSIZE.html
# OpenMP 5.2: Section 21.2.2, OMP_STACKSIZE.
# OpenMP specifies a positive integer with optional B/K/M/G unit; an unsupported
# size is implementation-defined. libgomp uses kilobytes when no unit is given.
# We validate syntax but do not test whether the runtime can allocate the size.
sub _validate_omp_stacksize {
    my ($value) = @_;
    return if $value =~ m/\A\s*[1-9]\d*\s*(?:[BKMG])?\s*\z/i;
    return q{Expected a positive integer optionally followed by B, K, M, or G};
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fSCHEDULE.html
# OpenMP 5.2: Section 21.2.1, OMP_SCHEDULE.
# OpenMP defines [MONOTONIC|NONMONOTONIC:]STATIC|DYNAMIC|GUIDED|AUTO[,chunk],
# with a positive chunk. The GCC/libgomp environment-variable page still
# documents the older type[,chunk] presentation and cites OpenMP 4.5. We accept
# the complete OpenMP 5.2 grammar; this is a deliberate standard-facing
# allowance, not a claim that libgomp's current prose explicitly documents the
# modifier syntax.
sub _validate_omp_schedule {
    my ($value) = @_;
    return if $value =~ m/\A\s*(?:(?:MONOTONIC|NONMONOTONIC)\s*:\s*)?(?:STATIC|DYNAMIC|GUIDED|AUTO)(?:\s*,\s*[1-9]\d*)?\s*\z/i;
    return q{Expected [MONOTONIC|NONMONOTONIC:]STATIC|DYNAMIC|GUIDED|AUTO optionally followed by a positive chunk};
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fTARGET_005fOFFLOAD.html
# OpenMP 5.2: Section 21.2.8, OMP_TARGET_OFFLOAD.
# OpenMP defines MANDATORY, DISABLED, and DEFAULT; OpenMP 5.2 specifically
# leaves support of DISABLED implementation-defined. GCC/libgomp explicitly
# implements all three spellings and documents host execution for DISABLED.
# We validate the token but do not probe target devices or offload plugins.
sub _validate_omp_target_offload { return _enum( shift, qw/MANDATORY DISABLED DEFAULT/ ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fTHREAD_005fLIMIT.html
# OpenMP 5.2: Section 21.1.3, OMP_THREAD_LIMIT.
# A positive integer is required; exceeding implementation capability is
# implementation-defined and deliberately not system-checked.
sub _validate_omp_thread_limit { return _integer_at_least( shift, 1 ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fWAIT_005fPOLICY.html
# OpenMP 5.2: Section 21.2.3, OMP_WAIT_POLICY.
# ACTIVE/PASSIVE are portable values, but the detailed waiting behavior is
# explicitly implementation-defined. We validate the token, not timing behavior.
sub _validate_omp_wait_policy { return _enum( shift, qw/ACTIVE PASSIVE/ ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/GOMP_005fCPU_005fAFFINITY.html
# OpenMP 5.2: no GOMP_CPU_AFFINITY variable; this is a GNU extension related to
# OMP_PLACES/OMP_PROC_BIND. libgomp accepts CPU numbers, M-N ranges, and M-N:S
# strides separated by spaces or commas; OMP_PROC_BIND takes precedence.
# We validate this GNU grammar but do not verify CPU identifiers on the host.
sub _validate_gomp_cpu_affinity {
    my ($value) = @_;
    my $entry = qr/\d+(?:-\d+(?::[1-9]\d*)?)?/;
    return if $value =~ m/\A\s*$entry(?:\s*(?:,|\s)\s*$entry)*\s*\z/;
    return q{Expected CPU numbers, M-N ranges, or M-N:S ranges separated by spaces or commas};
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/GOMP_005fDEBUG.html
# OpenMP 5.2: no GOMP_DEBUG variable; it is a GNU extension.
# libgomp documents 0/1. We validate only those GNU-defined values.
sub _validate_gomp_debug { return _enum( shift, qw/0 1/ ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/GOMP_005fSTACKSIZE.html
# OpenMP 5.2: no GOMP_STACKSIZE variable; OMP_STACKSIZE is the standard analogue.
# libgomp documents GOMP_STACKSIZE as a numeric kilobyte value with no unit
# suffix. Older OpenMP::Environment releases passed arbitrary values through, and
# the unchanged regression suite asserts an OMP_STACKSIZE-style suffixed value.
# To preserve that public behavior, both assignment and assertion accept B/K/M/G
# suffixes as an explicit OpenMP::Environment compatibility extension. This is
# NOT presented as documented libgomp syntax; callers wanting the GNU-native form
# should use an unsuffixed positive integer (kilobytes).
sub _validate_gomp_stacksize {
    my ($value) = @_;
    return if $value =~ m/\A\s*[1-9]\d*\s*(?:[BKMG])?\s*\z/i;
    return q{Expected a positive integer, with an optional B, K, M, or G OpenMP::Environment compatibility suffix};
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/GOMP_005fSPINCOUNT.html
# OpenMP 5.2: no GOMP_SPINCOUNT variable; it is a GNU extension.
# libgomp accepts INFINITE/INFINITY or a non-negative integer optionally suffixed
# by k/M/G/T multipliers. The number of CPUs can alter libgomp's effective spin
# behavior, but this portable validator checks syntax only.
sub _validate_gomp_spincount {
    my ($value) = @_;
    return if $value =~ m/\A\s*(?:INFINITE|INFINITY)\s*\z/i;
    return if $value =~ m/\A\s*\d+(?:k|M|G|T)?\s*\z/;
    return q{Expected INFINITE, INFINITY, or a non-negative integer optionally suffixed by k, M, G, or T};
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/GOMP_005fRTEMS_005fTHREAD_005fPOOLS.html
# OpenMP 5.2: no GOMP_RTEMS_THREAD_POOLS variable; it is a GNU/RTEMS extension.
# libgomp documents colon-separated count[$priority]@scheduler configurations.
# We validate that grammar only; scheduler names, RTEMS presence, and acceptable
# pthread priorities are intentionally not queried for portability.
sub _validate_gomp_rtems_thread_pools {
    my ($value) = @_;
    my $config = qr/[1-9]\d*(?:\$\d+)?\@[A-Za-z_][A-Za-z0-9_.-]*/;
    return if $value =~ m/\A\s*$config(?:\s*:\s*$config)*\s*\z/;
    return q{Expected colon-separated count[$priority]@scheduler configurations};
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fTEAMS_005fTHREAD_005fLIMIT.html
# OpenMP 5.2: Section 21.6.2, OMP_TEAMS_THREAD_LIMIT.
# A positive integer is portable. Target/runtime capability is not probed.
sub _validate_omp_teams_thread_limit { return _integer_at_least( shift, 1 ) }

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fALLOCATOR.html
# OpenMP 5.2: Section 21.5.1 plus Sections 6.1/6.2 (memory spaces/allocators).
# OpenMP permits a predefined allocator, a predefined memory space, or a memory
# space plus allocator traits. Several memory-space mappings and pool-size
# defaults are implementation-defined. libgomp additionally documents its GNU
# handling/mappings for implementation-defined allocators and GNU ompx_* names.
# OpenMP permits fb_data and allocator_fb. libgomp also lists allocator_fb as an
# allowed fallback token, but explicitly declares fb_data unsupported in the
# OMP_ALLOCATOR environment string because fb_data requires an allocator handle.
# We therefore accept fallback=allocator_fb as documented by libgomp, reject an
# explicit fb_data trait, and do not infer whether allocator_fb can provide a
# useful fallback without fb_data. We also do not test whether a memory space or
# allocator can actually be instantiated on the current runtime.
sub _validate_omp_allocator {
    my ($value) = @_;
    my $text = lc _trim($value);
    my %allocator = map { $_ => 1 } qw/
      omp_default_mem_alloc omp_large_cap_mem_alloc omp_const_mem_alloc
      omp_high_bw_mem_alloc omp_low_lat_mem_alloc omp_cgroup_mem_alloc
      omp_pteam_mem_alloc omp_thread_mem_alloc ompx_gnu_pinned_mem_alloc
      ompx_gnu_managed_mem_alloc
    /;
    my %space = map { $_ => 1 } qw/
      omp_default_mem_space omp_large_cap_mem_space omp_const_mem_space
      omp_high_bw_mem_space omp_low_lat_mem_space ompx_gnu_managed_mem_space
    /;

    return if $allocator{$text};
    return if $space{$text};

    my ( $memspace, $traits ) = $text =~ m/\A([^:]+):(.*)\z/;
    return q{Expected a predefined OpenMP allocator or memory space, optionally followed by allocator traits}
      if not defined $memspace;
    return q{Expected a predefined OpenMP allocator or memory space, optionally followed by allocator traits}
      if not $space{$memspace};
    return q{Allocator trait list must not be empty} if not length _trim($traits);

    my %seen;
    my %parsed;
    foreach my $pair ( split /\s*,\s*/, $traits ) {
        my ( $name, $trait_value ) = $pair =~ m/\A\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^\s,]+)\s*\z/;
        return q{Malformed allocator trait; expected name=value} if not defined $name;
        $name = lc $name;
        return qq{Duplicate allocator trait "$name"} if $seen{$name}++;
        my $err = _validate_allocator_trait( $name, $trait_value, \%allocator );
        return $err if defined $err;
        $parsed{$name} = $trait_value;
    }

    if ( defined $parsed{fb_data} ) {
        return q{fb_data is permitted by OpenMP but unsupported by GNU libgomp in OMP_ALLOCATOR};
    }
    return;
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fAFFINITY_005fFORMAT.html
# OpenMP 5.2: Section 21.2.5, OMP_AFFINITY_FORMAT.
# OpenMP defines percent field syntax and explicitly permits additional
# implementation-defined field types. A width is a positive decimal integer and
# may appear bare (%4L), right-justified (%.4L), or zero-padded for numeric fields
# (%0.4L). libgomp documents the standard short and long field names and the same
# width forms. OMP_AFFINITY_FORMAT is case-sensitive and its leading/trailing
# whitespace is significant, so validate_value deliberately does not trim it.
# Unknown alphabetic short/long fields are accepted as possible implementation-
# defined extensions. We validate syntax only and do not reject the standard's
# explicitly unspecified combinations such as zero-padding a nonnumeric field.
sub _validate_omp_affinity_format {
    my ($value) = @_;
    my $i = 0;
    while ( $i < length $value ) {
        my $pos = index( $value, q{%}, $i );
        return if $pos < 0;
        return q{Trailing percent sign in affinity format} if $pos == length($value) - 1;
        $i = $pos + 1;
        if ( substr( $value, $i, 1 ) eq q{%} ) {
            $i++;
            next;
        }
        my $tail = substr( $value, $i );
        my $width = qr/(?:[1-9]\d*|(?:0\.|\.)[1-9]\d*)?/;
        if ( $tail =~ m/\A$width([A-Za-z])/ ) {
            $i += length $&;
            next;
        }
        if ( $tail =~ m/\A$width\{[A-Za-z_][A-Za-z0-9_]*\}/ ) {
            $i += length $&;
            next;
        }
        return q{Malformed affinity field; expected %% or %[width]field or %[width]{field_name}};
    }
    return;
}

# GCC/libgomp: https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fDISPLAY_005fAFFINITY.html
# OpenMP 5.2: Section 21.2.4, OMP_DISPLAY_AFFINITY.
# TRUE/FALSE are defined; all other values have implementation-defined display
# behavior. libgomp implements the standard boolean forms. No affinity topology
# is queried by this validator.
sub _validate_omp_display_affinity { return _enum( shift, qw/TRUE FALSE/ ) }

sub _validate_allocator_trait {
    my ( $name, $value, $allocators ) = @_;
    if ( $name eq q{sync_hint} ) {
        return _enum( $value, qw/contended uncontended serialized private/ );
    }
    if ( $name eq q{alignment} ) {
        return q{alignment must be a positive power of two}
          if $value !~ m/\A[1-9]\d*\z/;
        return q{alignment must be a positive power of two}
          if ( $value & ( $value - 1 ) ) != 0;
        return;
    }
    if ( $name eq q{access} ) {
        return _enum( $value, qw/all cgroup pteam thread/ );
    }
    if ( $name eq q{pool_size} ) {
        return _integer_at_least( $value, 1 );
    }
    if ( $name eq q{fallback} ) {
        return _enum( $value, qw/default_mem_fb null_fb abort_fb allocator_fb/ );
    }
    if ( $name eq q{fb_data} ) {
        return undef if $allocators->{ lc $value };
        return q{fb_data must name a predefined allocator};
    }
    if ( $name eq q{pinned} ) {
        return _enum( $value, qw/true false/ );
    }
    if ( $name eq q{partition} ) {
        return _enum( $value, qw/environment nearest blocked interleaved/ );
    }
    return qq{Unknown allocator trait "$name"};
}

sub _trim {
    my ($value) = @_;
    $value =~ s/\A\s+//;
    $value =~ s/\s+\z//;
    return $value;
}

sub _split_top_level {
    my ( $text, $separator ) = @_;
    my @parts;
    my $part = q{};
    my ( $brace, $paren ) = ( 0, 0 );
    foreach my $char ( split //, $text ) {
        $brace++ if $char eq q[{];
        $brace-- if $char eq q[}];
        $paren++ if $char eq q{(};
        $paren-- if $char eq q{)};
        return () if $brace < 0;
        return () if $paren < 0;
        if ( $char eq $separator ) {
            if ( not $brace ) {
                if ( not $paren ) {
                    push @parts, _trim($part);
                    $part = q{};
                    next;
                }
            }
        }
        $part .= $char;
    }
    return () if $brace;
    return () if $paren;
    push @parts, _trim($part);
    return () if grep { $_ eq q{} } @parts;
    return @parts;
}

sub _validate_place_interval {
    my ($item) = @_;
    my $text = _trim($item);
    $text =~ s/\A!\s*//;

    my ( $base, $suffix );
    if ( substr( $text, 0, 1 ) eq q[{] ) {
        my $close = _matching_brace($text);
        return q{Unbalanced braces in OMP_PLACES} if $close < 0;
        $base = substr( $text, 0, $close + 1 );
        $suffix = substr( $text, $close + 1 );
        my $inside = substr( $base, 1, length($base) - 2 );
        my @resources = _split_top_level( $inside, q{,} );
        return q{Empty resource list in OMP_PLACES} if not @resources;
        foreach my $resource (@resources) {
            my $err = _validate_resource_interval($resource);
            return $err if defined $err;
        }
    }
    elsif ( $text =~ m/\A(\d+)(.*)\z/s ) {
        $base = $1;
        $suffix = $2;
    }
    else {
        return q{Expected an explicit place/resource or an abstract place name};
    }

    return if _trim($suffix) eq q{};
    return q{Malformed place interval; expected :length or :length:stride}
      if $suffix !~ m/\A\s*:\s*[1-9]\d*(?:\s*:\s*[+-]?\d+)?\s*\z/;
    return;
}

sub _validate_resource_interval {
    my ($resource) = @_;
    my $text = _trim($resource);
    $text =~ s/\A!\s*//;
    return if $text =~ m/\A\d+(?:\s*:\s*[1-9]\d*(?:\s*:\s*[+-]?\d+)?)?\z/;
    return q{Malformed OMP_PLACES resource; expected resource, resource:length, or resource:length:stride};
}

sub _matching_brace {
    my ($text) = @_;
    my $depth = 0;
    for my $i ( 0 .. length($text) - 1 ) {
        my $char = substr( $text, $i, 1 );
        $depth++ if $char eq q[{];
        if ( $char eq q[}] ) {
            $depth--;
            return $i if $depth == 0;
        }
    }
    return -1;
}

1;

__END__

=pod

=head1 NAME

OpenMP::Environment::Validation - portable OpenMP 5.2 and GNU libgomp environment validation

=head1 SYNOPSIS

  use OpenMP::Environment::Validation qw/
      validate_value assert_environment analyze_environment
  /;

  my $schedule = validate_value(
      q{OMP_SCHEDULE},
      q{nonmonotonic:dynamic,4},
  );

  assert_environment(\%ENV);  # dies on malformed or conflicting settings

  my $report = analyze_environment(\%ENV);
  print $report->{valid} ? "valid\n" : "needs attention\n";

=head1 PURPOSE

C<OpenMP::Environment::Validation> contains the validation policy used by
L<OpenMP::Environment>.  It is intentionally separate from the public
accessor/DSL module so the policy can be read, tested, and reused on its own.

The validation reference point is OpenMP 5.2 together with GNU libgomp as
shipped/documented with GCC 16.2.0.  The module distinguishes between:

=over 4

=item * INVALID

A value does not satisfy this module's selected validation profile: the OpenMP
5.2 grammar, plus an explicitly documented GCC/libgomp restriction when GNU's
documented grammar is narrower.  Such GNU-profile restrictions are called out
individually rather than being presented as portable OpenMP requirements.

=item * CONFLICT / IMPLEMENTATION-DEFINED COMBINATION

Each individual value is syntactically valid, but OpenMP explicitly says the
combination is implementation-defined.  The principal 5.2 case handled here is
C<OMP_NESTED=FALSE> together with C<OMP_MAX_ACTIVE_LEVELS> greater than one.

=item * VALID BUT RUNTIME-DEPENDENT

The syntax is valid but whether the request can be honored depends on runtime
resources, topology, target devices, allocators, or implementation limits.
These values pass validation and are reported by C<analyze_environment>.

=back

=head1 PORTABILITY SCOPE AND NON-GOALS

This module is deliberately B<not> system-aware.  It does not inspect CPU
counts, CPU identifiers, NUMA topology, hwloc, GPUs, target devices, available
allocators, C</proc>, compiler executables, runtime state, or operating-system
resources.  Such checks can be useful, but they introduce portability and
load-time concerns that belong in a future, explicitly system-aware layer.

Consequently, values such as these are syntactically valid here even though a
particular runtime may be unable to honor them:

  OMP_DEFAULT_DEVICE=7
  OMP_PLACES={0,1,2,3}
  OMP_STACKSIZE=64G
  OMP_THREAD_LIMIT=100000

=head1 OPENMP VALUE SYNTAX AND NORMALIZATION

OpenMP 5.2 Chapter 21 states that OpenMP environment-variable values are
generally case-insensitive and may contain leading and trailing whitespace.
Strict validation therefore ignores surrounding whitespace for supported
C<OMP_*> variables before validating them.  The established upper-case
normalization used by C<OpenMP::Environment> is retained for its historical
boolean/token fields.

C<OMP_AFFINITY_FORMAT> is the important exception.  Section 21.2.5 explicitly
states that its value is case-sensitive and that leading and trailing
whitespace is significant.  This module therefore preserves that string
exactly.

The C<GOMP_*> variables are GNU extensions rather than OpenMP Chapter 21
variables; their syntax follows the libgomp documentation rather than assuming
that every general OpenMP lexical rule applies to them.

=head1 API

=head2 validate_value NAME, VALUE

Validates one supported C<OMP_*> or C<GOMP_*> value and returns the value after
normalization.  For C<OMP_*> values, surrounding whitespace is ignored except
for C<OMP_AFFINITY_FORMAT>, where it is significant.  The same six variables
upper-cased by older C<OpenMP::Environment> releases continue to be upper-cased.
Dies on invalid input.

=head2 validate_assignment NAME, VALUE

Applies the validation policy used by ordinary/lvalue assignment in
C<OpenMP::Environment>.  To preserve pre-1.5.0 compatibility, variables that
were historically pass-through remain pass-through here.  Use C<validate_value>
or C<assert> for strict grammar validation of all supported variables.

=head2 assert_variable ENV, NAME

Validates one value from a hash reference and checks cross-variable conflicts
that involve that variable.  An unset variable is valid.

=head2 assert_environment ENV

Validates every supported variable present in the supplied hash and then checks
portable cross-variable conflicts.  As with historical
C<assert_omp_environment>, normalized values are written back to the hash.

=head2 analyze_environment ENV

Returns a machine-readable hash reference with these keys:

  valid
  errors
  conflicts
  runtime_dependent
  notes

It never performs host/resource discovery.

=head2 validation_rules

Returns introspection metadata describing the supported fields, historical
upper-case normalization, variables validated on ordinary assignment, fields
whose whitespace is significant, validator routines, and the validation profile.
This is intended to make the policy useful to machine consumers as well as to
human readers of this POD.

=head1 PER-VARIABLE REFERENCE

=head2 OMP_NUM_THREADS

OpenMP 5.2 Section 21.1.2 permits one positive integer or a comma-separated
list for nested parallel levels.  GCC/libgomp implements that syntax.  Values
larger than runtime capability are implementation-dependent, so this module
checks only the positive-integer grammar.

  Valid:   OMP_NUM_THREADS=8
  Valid:   OMP_NUM_THREADS=8,4,2
  Invalid: OMP_NUM_THREADS=8,0,2

GCC/libgomp:
L<https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fNUM_005fTHREADS.html>

OpenMP 5.2:
L<https://www.openmp.org/spec-html/5.2/openmp.html>, Section 21.1.2.

=head2 OMP_MAX_ACTIVE_LEVELS

OpenMP 5.2 Section 21.1.4 permits a B<non-negative> integer, so zero is valid
according to the OpenMP grammar.  GCC/libgomp documents this environment
variable more narrowly as a B<positive> integer.  Earlier
C<OpenMP::Environment> releases also rejected zero.  Because this distribution
is explicitly profiled against GCC 16.2/libgomp, strict validation retains the
GNU/legacy positive-integer rule.

  Valid in this GCC/libgomp profile: OMP_MAX_ACTIVE_LEVELS=1
  OpenMP-valid but rejected here:   OMP_MAX_ACTIVE_LEVELS=0
  Invalid:                          OMP_MAX_ACTIVE_LEVELS=-1

Values above the maximum nesting level supported by a particular runtime are
implementation-defined and are not system-probed here.

GCC/libgomp:
L<https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fMAX_005fACTIVE_005fLEVELS.html>

OpenMP 5.2: Section 21.1.4 and Appendix A.

=head2 OMP_PROC_BIND

OpenMP 5.2 Section 21.1.7 specifies C<TRUE>, C<FALSE>, or a list of
C<PRIMARY>, C<CLOSE>, and C<SPREAD>.  OpenMP deprecates the older C<MASTER>
spelling; GNU libgomp deliberately retains it, so this module accepts it.
Binding to actual places and the policy chosen for C<TRUE> remain
implementation-dependent.

  Valid:   OMP_PROC_BIND=close
  Valid:   OMP_PROC_BIND=spread,close,primary
  GNU:     OMP_PROC_BIND=master,close,spread
  Invalid: OMP_PROC_BIND=near

GCC/libgomp:
L<https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fPROC_005fBIND.html>

OpenMP 5.2: Section 21.1.7 and Appendix A.

=head2 OMP_PLACES

OpenMP 5.2 Section 21.1.6 defines abstract names, explicit place/resource
lists, intervals, strides, and exclusions.  It intentionally leaves resource
numbering, exact abstract-name meaning, and additional abstract names to the
implementation.  GNU libgomp documents C<threads>, C<cores>, C<sockets>,
C<ll_caches>, and C<numa_domains> plus explicit list syntax.

  Valid:   OMP_PLACES=cores
  Valid:   OMP_PLACES=cores(4)
  Valid:   OMP_PLACES={0,1,2},{3,4,5}
  Valid:   OMP_PLACES={0:4},{4:4}
  Valid:   OMP_PLACES=!{0},1:3
  Invalid: OMP_PLACES={0,,2}

This module checks grammar but does not decide whether processor 4 exists or
what C<cores> means on the current machine.

GCC/libgomp:
L<https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/OMP_005fPLACES.html>

OpenMP 5.2: Section 21.1.6 and Appendix A.

=head2 OMP_SCHEDULE

OpenMP 5.2 Section 21.2.1 defines:

  [modifier:]kind[,chunk]

where modifier is C<MONOTONIC> or C<NONMONOTONIC>, kind is C<STATIC>,
C<DYNAMIC>, C<GUIDED>, or C<AUTO>, and chunk is a positive integer.  GNU
libgomp documentation emphasizes the simpler C<type[,chunk]> spelling; the
full OpenMP 5.2 grammar is accepted here because it includes all GNU-documented
forms.

  Valid:   OMP_SCHEDULE=dynamic,4
  Valid:   OMP_SCHEDULE=monotonic:guided,8
  Invalid: OMP_SCHEDULE=banana
  Invalid: OMP_SCHEDULE=dynamic,0

OpenMP specifies implementation-defined behavior for malformed values; this
module instead rejects malformed values early.

=head2 OMP_STACKSIZE and GOMP_STACKSIZE

OpenMP 5.2 Section 21.2.2 specifies a positive size with optional C<B>, C<K>,
C<M>, or C<G> unit for C<OMP_STACKSIZE>; libgomp uses kilobytes when the unit
is omitted.  Whether the requested stack can actually be provided is
implementation-dependent and is not checked.

GNU C<GOMP_STACKSIZE> is an extension documented as a positive numeric value
in kilobytes, with no unit suffix.  Older C<OpenMP::Environment> releases did
not validate this variable, and the unchanged regression suite includes and
asserts a unit-suffixed value.  Version 1.5.0 therefore accepts C<B>, C<K>,
C<M>, and C<G> suffixes as an explicit B<OpenMP::Environment compatibility
extension> in both assignment and assertion.  This POD does not claim those
suffixes are valid libgomp C<GOMP_STACKSIZE> syntax; the GNU-native spelling is
an unsuffixed positive integer interpreted as kilobytes.

=head2 OMP_ALLOCATOR

OpenMP 5.2 Section 21.5.1 and Sections 6.1-6.2 define predefined allocators,
predefined memory spaces, and allocator traits.  This module checks the trait
vocabulary and intrinsic constraints including positive power-of-two
C<alignment>, positive C<pool_size>, booleans, fallback values, and predefined
allocator traits.  OpenMP permits C<fb_data> for C<allocator_fb>.  GNU libgomp
still lists C<allocator_fb> as an allowed C<fallback> token, but explicitly marks
C<fb_data> unsupported in the C<OMP_ALLOCATOR> environment string because it
requires an allocator handle.  Strict validation therefore accepts the
documented C<fallback=allocator_fb> token, rejects an explicit C<fb_data> trait,
and deliberately does not infer whether a useful allocator fallback can be
constructed without C<fb_data>.  Ordinary assignment remains pass-through for
compatibility.

  Valid: OMP_ALLOCATOR=omp_high_bw_mem_alloc
  Valid: OMP_ALLOCATOR=omp_large_cap_mem_space:alignment=16,pinned=true
  Valid: OMP_ALLOCATOR=omp_low_lat_mem_space:fallback=allocator_fb
  GNU:   OMP_ALLOCATOR=ompx_gnu_pinned_mem_alloc
  Invalid: OMP_ALLOCATOR=omp_low_lat_mem_space:alignment=3
  libgomp-invalid: OMP_ALLOCATOR=omp_default_mem_space:fb_data=omp_default_mem_alloc

OpenMP explicitly leaves actual storage-resource mappings, some predefined
allocator memory-space associations, partition minimums, and the default pool
size implementation-defined.  GNU libgomp maps the cgroup/pteam/thread
allocators to C<omp_low_lat_mem_space> as an implementation choice and also
provides C<ompx_gnu_pinned_mem_alloc>, C<ompx_gnu_managed_mem_alloc>, and
C<ompx_gnu_managed_mem_space> as GNU extensions.  Availability is not probed.

Memory allocator trait definitions:
L<https://www.openmp.org/spec-html/5.2/openmpse35.html>

=head2 OMP_AFFINITY_FORMAT

OpenMP 5.2 Section 21.2.5 specifies a percent-field format and permits
implementation-defined additional field types.  A field width is a positive
decimal integer and can be written as a bare minimum width (C<%4L>), as a
right-justified width (C<%.4L>), or with zero padding for numeric fields
(C<%0.4L>).  GNU libgomp documents the same width forms and the standard short
and long field names.  Syntactically valid unknown alphabetic field names are
accepted as possible implementation extensions.

The value is case-sensitive and leading/trailing whitespace is significant;
strict validation preserves it rather than applying the general OpenMP
whitespace normalization.  OpenMP says the result is unspecified when the
zero-padding modifier is used for a nonnumeric field; that is not a syntax
error, so this validator does not reject it.

  Valid:   OMP_AFFINITY_FORMAT=thread %n affinity %A
  Valid:   OMP_AFFINITY_FORMAT=level %4L thread %0.2n
  Valid:   OMP_AFFINITY_FORMAT=host %.12{host}
  Valid:   OMP_AFFINITY_FORMAT=%% %n
  Invalid: OMP_AFFINITY_FORMAT=thread %
  Invalid: OMP_AFFINITY_FORMAT=level %.0L

=head2 GOMP_CPU_AFFINITY

This is a GNU extension, not an OpenMP environment variable.  libgomp accepts
space/comma-separated CPU numbers, ranges C<M-N>, and stride ranges C<M-N:S>.
C<OMP_PROC_BIND> has precedence when both variables are set.

  Valid:   GOMP_CPU_AFFINITY=0 3 1-2 4-15:2
  Invalid: GOMP_CPU_AFFINITY=cpu0

CPU existence is not checked.

=head2 GOMP_SPINCOUNT

This GNU extension accepts C<INFINITE>, C<INFINITY>, or a non-negative integer
optionally suffixed by C<k>, C<M>, C<G>, or C<T>.  Effective busy-wait behavior
can depend on C<OMP_WAIT_POLICY> and available CPUs; only syntax is checked.

  Valid:   GOMP_SPINCOUNT=300000
  Valid:   GOMP_SPINCOUNT=30G
  Valid:   GOMP_SPINCOUNT=INFINITY
  Invalid: GOMP_SPINCOUNT=forever

=head2 GOMP_RTEMS_THREAD_POOLS

This GNU/RTEMS-only variable uses colon-separated
C<count[$priority]@scheduler> configurations.  The documented libgomp example
C<1@WRK0:3$4@WRK1> is valid.  Scheduler existence and permissible RTEMS
priority ranges are not queried.

=head2 Other scalar and token variables

The remaining standard variables use smaller grammars but still have
implementation-defined edges worth distinguishing from syntax errors:

=over 4

=item * C<OMP_CANCELLATION> and C<OMP_DISPLAY_AFFINITY>

C<TRUE> or C<FALSE>.  OpenMP makes other values implementation-defined for
C<OMP_CANCELLATION> and makes the display action implementation-defined for
other C<OMP_DISPLAY_AFFINITY> values.

=item * C<OMP_DISPLAY_ENV>

C<TRUE>, C<FALSE>, or C<VERBOSE>.  OpenMP says the displayed information is
unspecified for other values.

=item * C<OMP_DEFAULT_DEVICE> and C<OMP_MAX_TASK_PRIORITY>

Non-negative integers.  Device existence and runtime priority capability are
not probed.

=item * C<OMP_DYNAMIC> and deprecated C<OMP_NESTED>

OpenMP defines boolean values.  C<OpenMP::Environment> additionally retains
its historical C<1>/C<0> compatibility.  C<OMP_NESTED> also participates in
the cross-variable rule documented below.

=item * C<OMP_NUM_TEAMS>, C<OMP_TEAMS_THREAD_LIMIT>, and C<OMP_THREAD_LIMIT>

Positive integers.  OpenMP makes behavior implementation-defined when a value
is invalid or exceeds an implementation limit; this module validates syntax
but does not query those limits.

=item * C<OMP_TARGET_OFFLOAD>

C<MANDATORY>, C<DISABLED>, or C<DEFAULT>.  OpenMP 5.2 makes support of
C<DISABLED> implementation-defined; GCC/libgomp explicitly implements all
three values.

=item * C<OMP_WAIT_POLICY>

C<ACTIVE> or C<PASSIVE>.  The detailed waiting behavior is implementation-
defined.

=item * C<GOMP_DEBUG>

GNU extension accepting C<0> or C<1>.

=back

=head1 CROSS-VARIABLE RULES

=head2 OMP_NESTED and OMP_MAX_ACTIVE_LEVELS

OpenMP 5.2 explicitly says behavior is implementation-defined when both are
set, C<OMP_NESTED> is false, and C<OMP_MAX_ACTIVE_LEVELS> is greater than one.
C<assert_environment> treats this as a conflict:

  OMP_NESTED=FALSE
  OMP_MAX_ACTIVE_LEVELS=4

If both are set without that conflict, OpenMP says C<OMP_NESTED> has no effect.

=head2 OMP_NUM_THREADS / OMP_PROC_BIND nesting lists

Multiple list elements can affect initialization of C<max-active-levels-var>.
OpenMP 5.2 Section 2.2 describes that ICV as depending on
C<OMP_MAX_ACTIVE_LEVELS>, C<OMP_NESTED>, C<OMP_NUM_THREADS>, and
C<OMP_PROC_BIND>.  A list is not itself an error; C<analyze_environment>
records the relationship as a note.

=head2 OMP_PROC_BIND and GOMP_CPU_AFFINITY

GNU libgomp gives C<OMP_PROC_BIND> precedence if both are set.  This is a valid
configuration, not a conflict; C<analyze_environment> records the precedence.

=head1 IMPLEMENTATION-DEFINED VERSUS GNU CHOICES

OpenMP deliberately leaves several matters to implementations.  Important
examples include processor numbering and abstract C<OMP_PLACES> meanings,
actual affinity policy for C<OMP_PROC_BIND=TRUE>, maximum supported thread and
active-level counts, ability to provide a requested stack, memory-space
mappings for several predefined allocators, allocator pool defaults, and the
details of active/passive waiting.

GNU libgomp necessarily chooses concrete behavior in many of those areas and
also provides C<GOMP_*> extensions.  This module validates GNU-documented
syntax where it is portable to do so, but it does not turn a GNU runtime choice
into a supposed cross-platform OpenMP guarantee.

The OpenMP implementation-defined behavior index is:
L<https://www.openmp.org/spec-html/5.2/openmpap1.html>.

The GCC/libgomp environment-variable index is:
L<https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/Environment-Variables.html>.

=head1 COPYRIGHT AND LICENSE

Same as Perl.

=for Pod::Coverage _validate_omp_cancellation _validate_omp_display_env _validate_omp_default_device _validate_omp_num_teams _validate_omp_dynamic _validate_omp_max_active_levels _validate_omp_max_task_priority _validate_omp_nested _validate_omp_num_threads _validate_omp_proc_bind _validate_omp_places _validate_omp_stacksize _validate_omp_schedule _validate_omp_target_offload _validate_omp_thread_limit _validate_omp_wait_policy _validate_gomp_cpu_affinity _validate_gomp_debug _validate_gomp_stacksize _validate_gomp_spincount _validate_gomp_rtems_thread_pools _validate_omp_teams_thread_limit _validate_omp_allocator _validate_omp_affinity_format _validate_omp_display_affinity _validate_allocator_trait _runtime_note _is_false _has_multiple_items _has_proc_bind_list _enum _integer_at_least _positive_integer_list _trim _split_top_level _validate_place_interval _validate_resource_interval _matching_brace

=cut

