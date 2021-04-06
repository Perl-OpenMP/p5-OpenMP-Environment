package OpenMP::Environment;

use strict;
use warnings;

use Validate::Tiny qw/filter is_in/;

our @_OMP_VARS = (
    qw/OMP_CANCELLATION OMP_DISPLAY_ENV OMP_DEFAULT_DEVICE
      OMP_DYNAMIC OMP_MAX_ACTIVE_LEVELS OMP_MAX_TASK_PRIORITY OMP_NESTED
      OMP_NUM_THREADS OMP_PROC_BIND OMP_PLACES OMP_STACKSIZE OMP_SCHEDULE
      OMP_TARGET_OFFLOAD OMP_THREAD_LIMIT OMP_WAIT_POLICY GOMP_CPU_AFFINITY
      GOMP_DEBUG GOMP_STACKSIZE GOMP_SPINCOUNT GOMP_RTEMS_THREAD_POOLS/
);

# capture state of %ENV
local %ENV = %ENV;

# constructor
sub new {
    my $pkg = shift;

    my $validate_rules = {
        fields  => \@_OMP_VARS,
        filters => [
            [qw/OMP_CANCELLATION OMP_DYNAMIC OMP_NESTED OMP_DISPLAY_ENV OMP_TARGET_OFFLOAD OMP_WAIT_POLICY/] => filter('uc'), # force to upper case for convenience
        ],
        checks => [
            [qw/OMP_CANCELLATION OMP_DYNAMIC OMP_NESTED/]                => is_in( [qw/TRUE FALSE/],                 q{Expected values are: 'TRUE' or 'FALSE'} ),
            OMP_DISPLAY_ENV                                              => is_in( [qw/TRUE VERBOSE FALSE/],         q{Expected values are: 'TRUE', 'VERBOSE', or 'FALSE'} ),
            OMP_TARGET_OFFLOAD                                           => is_in( [qw/MANDATORY DISABLED DEFAULT/], q{Expected values are: 'MANDATORY', 'DISABLED', or 'DEFAULT'} ),
            OMP_WAIT_POLICY                                              => is_in( [qw/ACTIVE PASSIVE/],             q{Expected values are: 'ACTIVE' or 'PASSIVE'} ),
            GOMP_DEBUG                                                   => is_in( [qw/0 1/],                        q{Expected values are: 0 or 1} ),
            [qw/OMP_MAX_TASK_PRIORITY OMP_DEFAULT_DEVICE/]               => sub { return _is_ge_if_set( 0, @_ ) },
            [qw/OMP_NUM_THREADS OMP_MAX_ACTIVE_LEVELS OMP_THREAD_LIMIT/] => sub { return _is_ge_if_set( 1, @_ ) },
            OMP_PROC_BIND                                                => _no_validate(),
            OMP_PLACES                                                   => _no_validate(),
            OMP_STACKSIZE                                                => _no_validate(),
            OMP_SCHEDULE                                                 => _no_validate(),
            GOMP_CPU_AFFINITY                                            => _no_validate(),
            GOMP_STACKSIZE                                               => _no_validate(),
            GOMP_SPINCOUNT                                               => _no_validate(),
            GOMP_RTEMS_THREAD_POOLS                                      => _no_validate(),
        ],
    };

    sub _is_ge_if_set {
        my ( $min, $value ) = @_;
        if ( not defined $value ) {
            return;
        }
        elsif ( $value =~ m/\D/ or $value lt $min ) {
            return q{Value must be an integer great than or equal to 1};
        }
        return;
    }

    my $self = { _validation_rules => $validate_rules, };
    return bless $self, $pkg;
}

# returns a list of variables supported (no values)
sub vars {
    my $self = shift;
    return @_OMP_VARS;
}

# returns a list of variables unset (value not set so don't need it)
sub vars_unset {
    my $self  = shift;
    my @unset = ();
    foreach my $ev (@_OMP_VARS) {
        push @unset, $ev if not $ENV{$ev};
    }
    return @unset;
}

# returns a list of all variables that are currently set, and their values
# as an array of hash references of the form, "$VAR_NAME => $value"
sub vars_set {
    my $self = shift;
    my @set  = ();
    foreach my $ev (@_OMP_VARS) {
        push @set, { $ev => $ENV{$ev} } if $ENV{$ev};
    }
    return @set;
}

sub print_summary_unset {
    my $self  = shift;
    my @lines = ();
    push @lines, qq{Summary of OpenMP Environmental UNSET variables supported in this module:};
  ENV:
    foreach my $ev ( $self->vars_unset ) {
        push @lines, sprintf( qq{%s}, $ev );
    }
    print join( qq{\n}, @lines );
    print qq{\n};
    print qq{- none\n} if ( @lines == 1 );
}

sub print_summary_set {
    my $self  = shift;
    my @lines = ();
    push @lines, qq{Summary of OpenMP Environmental SET variables supported in this module:};
  ENV:
    foreach my $ev_ref ( $self->vars_set ) {
        my $ev  = ( keys %$ev_ref )[0];
        my $val = ( values %$ev_ref )[0];
        push @lines, sprintf( qq{%-25s %s}, $ev, $val );
    }
    print join( qq{\n}, @lines );
    print qq{\n};
    print qq{- none\n} if ( @lines == 1 );
}

sub print_summary {
    my $self = shift;
    print qq{Summary of OpenMP Environmental ALL variables supported in this module:\n};
    printf( qq{%-25s %s\n}, q{Variable}, q{Value} );
    printf( qq{%-25s %s\n}, q{~~~~~~~~}, q{~~~~~} );
  ENV:
    foreach my $ev ( $self->vars ) {
        my $val = ( $ENV{$ev} ) ? $ENV{$ev} : q{<XXunsetXX>};
        printf( qq{%-25s %s\n}, $ev, $val );
    }
}

# OpenMP Environmental Variable setters/getters

sub omp_cancellation {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_CANCELLATION};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_cancellation {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_CANCELLATION};
    return delete $ENV{$ev};
}

sub omp_display_env {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DISPLAY_ENV};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_display_env {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DISPLAY_ENV};
    return delete $ENV{$ev};
}

sub omp_default_device {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DEFAULT_DEVICE};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_default_device {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DEFAULT_DEVICE};
    return delete $ENV{$ev};
}

sub omp_dynamic {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DYNAMIC};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_dynamic {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DYNAMIC};
    return delete $ENV{$ev};
}

sub omp_max_active_levels {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_MAX_ACTIVE_LEVELS};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_max_active_levels {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_MAX_ACTIVE_LEVELS};
    return delete $ENV{$ev};
}

sub omp_max_task_priority {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_MAX_TASK_PRIORITY};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_max_task_priority {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_MAX_TASK_PRIORITY};
    return delete $ENV{$ev};
}

sub omp_nested {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_NESTED};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_nested {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_NESTED};
    return delete $ENV{$ev};
}

sub omp_num_threads {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_NUM_THREADS};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_num_threads {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_NUM_THREADS};
    return delete $ENV{$ev};
}

sub omp_proc_bind {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_PROC_BIND};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_proc_bind {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_PROC_BIND};
    return delete $ENV{$ev};
}

sub omp_places {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_PLACES};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_places {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_PLACES};
    return delete $ENV{$ev};
}

sub omp_stacksize {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_STACKSIZE};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_stacksize {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_STACKSIZE};
    return delete $ENV{$ev};
}

sub omp_schedule {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_SCHEDULE};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_schedule {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_SCHEDULE};
    return delete $ENV{$ev};
}

sub omp_target_offload {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_TARGET_OFFLOAD};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_target_offload {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_TARGET_OFFLOAD};
    return delete $ENV{$ev};
}

sub omp_thread_limit {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_THREAD_LIMIT};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_thread_limit {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_THREAD_LIMIT};
    return delete $ENV{$ev};
}

sub omp_wait_policy {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_WAIT_POLICY};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_omp_wait_policy {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_WAIT_POLICY};
    return delete $ENV{$ev};
}

sub gomp_cpu_affinity {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_CPU_AFFINITY};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_gomp_cpu_affinity {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_CPU_AFFINITY};
    return delete $ENV{$ev};
}

sub gomp_debug {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_DEBUG};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_gomp_debug {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_DEBUG};
    return delete $ENV{$ev};
}

sub gomp_stacksize {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_STACKSIZE};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_gomp_stacksize {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_STACKSIZE};
    return delete $ENV{$ev};
}

sub gomp_spincount {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_SPINCOUNT};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_gomp_spincount {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_SPINCOUNT};
    return delete $ENV{$ev};
}

sub gomp_rtems_thread_pools {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_RTEMS_THREAD_POOLS};
    return $self->_get_set_assert( $ev, $value );
}

sub unset_gomp_rtems_thread_pools {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_RTEMS_THREAD_POOLS};
    return delete $ENV{$ev};
}

# auxilary validation routines for with Validate::Tiny

sub _get_set_assert {
    my ( $self, $ev, $value ) = @_;
    if ( defined $value ) {
        my $filtered_value = $self->_assert_valid( $ev, $value );
        $ENV{$ev} = $filtered_value;
    }
    return (exists $ENV{$ev}) ? $ENV{$ev} : undef;
}

sub _assert_valid {
    my ( $self, $ev, $value ) = @_;
    my $result = Validate::Tiny::validate( { $ev => $value }, $self->{_validation_rules} );

    # process errors, then die
    my $err;
    foreach my $e ( keys %{ $result->{error} } ) {
        my $msg = $result->{error}->{$e};
        my $val = $result->{data}->{$e};
        $err = qq{(fatal) $e="$val": $msg\n};
    }
    die qq{$err\n} if not $result->{success};

    # if all is okay, return the filtered value (since we're testing what's been passed through 'filters' for some envars
    return $result->{data}->{$ev};
}

# provides validator that does nothing, a null validator useful as a place holder
sub _no_validate {
    return sub {
        return undef;
    };
}

1;

__END__

=head1 NAME

OpenMP::Environment - Perl extension managing OpenMP environmental variables within a script.

=head1 SYNOPSIS

  use OpenMP::Environment;

  my $ompenv = OpenMP::Environment->new;

  # assert valid environment; will warn if no OMP_* variables are set; will will `die` if any
  # supported variables are set incorrectly; by default, will warn if C<OMP_NUM_THREADS> is not set.

  $ompenv->validate_environment;

=head1 DESCRIPTION

Provides accessors for affecting the OpenMP/GOMP environmental
variables described at at the time of this writing, as:

C<The environment variables which beginning with OMP_ are defined
by section 4 of the OpenMP specification in version 4.5, while
those beginning with GOMP_ are GNU extensions.>

L<https://gcc.gnu.org/onlinedocs/libgomp/Environment-Variables.html>

=head1 SUPPORTED C<OpenMP> ENVIRONMENTAL VARIABLES

Essentially direct copy from the URL in L<DESCRIPTION>.

=over 3

=item C<OMP_CANCELLATION>

If set to TRUE, the cancellation is activated. If set to FALSE or if unset, cancellation is disabled and the cancel construct is ignored.

=item C<OMP_DISPLAY_ENV>

If set to TRUE, the OpenMP version number and the values associated with the OpenMP environment variables are printed to stderr. If set to VERBOSE, it additionally shows the value of the environment variables which are GNU extensions. If undefined or set to FALSE, this information will not be shown.

=item C<OMP_DEFAULT_DEVICE>

Set to choose the device which is used in a target region, unless the value is overridden by omp_get_set_assert_default_device or by a device clause. The value shall be the nonnegative device number. If no device with the given device number exists, the code is executed on the host. If unset, device number 0 will be used.

=item C<OMP_DYNAMIC>

Enable or disable the dynamic adjustment of the number of threads within a team. The value of this environment variable shall be TRUE or FALSE. If undefined, dynamic adjustment is disabled by default.

=item C<OMP_MAX_ACTIVE_LEVELS>

Specifies the initial value for the maximum number of nested parallel regions. The value of this variable shall be a positive integer. If undefined, then if OMP_NESTED is defined and set to true, or if OMP_NUM_THREADS or OMP_PROC_BIND are defined and set to a list with more than one item, the maximum number of nested parallel regions will be initialized to the largest number supported, otherwise it will be set to one.

=item C<OMP_MAX_TASK_PRIORITY>

Specifies the initial value for the maximum priority value that can be set for a task. The value of this variable shall be a non-negative integer, and zero is allowed. If undefined, the default priority is 0.

=item C<OMP_NESTED>

Enable or disable nested parallel regions, i.e., whether team members are allowed to create new teams. The value of this environment variable shall be TRUE or FALSE. If set to TRUE, the number of maximum active nested regions supported will by default be set to the maximum supported, otherwise it will be set to one. If OMP_MAX_ACTIVE_LEVELS is defined, its setting will override this setting. If both are undefined, nested parallel regions are enabled if OMP_NUM_THREADS or OMP_PROC_BINDS are defined to a list with more than one item, otherwise they are disabled by default.

=item C<OMP_NUM_THREADS>

Specifies the default number of threads to use in parallel regions. The value of this variable shall be a comma-separated list of positive integers; the value specifies the number of threads to use for the corresponding nested level. Specifying more than one item in the list will automatically enable nesting by default. If undefined one thread per CPU is used.

=item C<OMP_PROC_BIND>

Specifies whether threads may be moved between processors. If set to TRUE, OpenMP theads should not be moved; if set to FALSE they may be moved. Alternatively, a comma separated list with the values MASTER, CLOSE and SPREAD can be used to specify the thread affinity policy for the corresponding nesting level. With MASTER the worker threads are in the same place partition as the master thread. With CLOSE those are kept close to the master thread in contiguous place partitions. And with SPREAD a sparse distribution across the place partitions is used. Specifying more than one item in the list will automatically enable nesting by default.

When undefined, OMP_PROC_BIND defaults to TRUE when OMP_PLACES or GOMP_CPU_AFFINITY is set and FALSE otherwise.

=item C<OMP_PLACES>

The thread placement can be either specified using an abstract name or by an explicit list of the places. The abstract names threads, cores and sockets can be optionally followed by a positive number in parentheses, which denotes the how many places shall be created. With threads each place corresponds to a single hardware thread; cores to a single core with the corresponding number of hardware threads; and with sockets the place corresponds to a single socket. The resulting placement can be shown by setting the OMP_DISPLAY_ENV environment variable.

Alternatively, the placement can be specified explicitly as comma-separated list of places. A place is specified by set of nonnegative numbers in curly braces, denoting the denoting the hardware threads. The hardware threads belonging to a place can either be specified as comma-separated list of nonnegative thread numbers or using an interval. Multiple places can also be either specified by a comma-separated list of places or by an interval. To specify an interval, a colon followed by the count is placed after after the hardware thread number or the place. Optionally, the length can be followed by a colon and the stride number – otherwise a unit stride is assumed. For instance, the following specifies the same places list: "{0,1,2}, {3,4,6}, {7,8,9}, {10,11,12}"; "{0:3}, {3:3}, {7:3}, {10:3}"; and "{0:2}:4:3".

If OMP_PLACES and GOMP_CPU_AFFINITY are unset and OMP_PROC_BIND is either unset or false, threads may be moved between CPUs following no placement policy.

=item C<OMP_STACKSIZE>

Set the default thread stack size in kilobytes, unless the number is suffixed by B, K, M or G, in which case the size is, respectively, in bytes, kilobytes, megabytes or gigabytes. This is different from pthread_attr_get_set_assertstacksize which gets the number of bytes as an argument. If the stack size cannot be set due to system constraints, an error is reported and the initial stack size is left unchanged. If undefined, the stack size is system dependent.

=item C<OMP_SCHEDULE>

Allows to specify schedule type and chunk size. The value of the variable shall have the form: type[,chunk] where type is one of static, dynamic, guided or auto The optional chunk size shall be a positive integer. If undefined, dynamic scheduling and a chunk size of 1 is used.

=item C<OMP_TARGET_OFFLOAD>

Specifies the behaviour with regard to offloading code to a device. This variable can be set to one of three values - MANDATORY, DISABLED or DEFAULT.

If set to MANDATORY, the program will terminate with an error if the offload device is not present or is not supported. If set to DISABLED, then offloading is disabled and all code will run on the host. If set to DEFAULT, the program will try offloading to the device first, then fall back to running code on the host if it cannot.

If undefined, then the program will behave as if DEFAULT was set.

=item C<OMP_THREAD_LIMIT>

Specifies the number of threads to use for the whole program. The value of this variable shall be a positive integer. If undefined, the number of threads is not limited.

=item C<OMP_WAIT_POLICY>

Specifies whether waiting threads should be active or passive. If the value is PASSIVE, waiting threads should not consume CPU power while waiting; while the value is ACTIVE specifies that they should. If undefined, threads wait actively for a short time before waiting passively.

=item C<GOMP_CPU_AFFINITY>

Binds threads to specific CPUs. The variable should contain a space-separated or comma-separated list of CPUs. This list may contain different kinds of entries: either single CPU numbers in any order, a range of CPUs (M-N) or a range with some stride (M-N:S). CPU numbers are zero based. For example, GOMP_CPU_AFFINITY="0 3 1-2 4-15:2" will bind the initial thread to CPU 0, the second to CPU 3, the third to CPU 1, the fourth to CPU 2, the fifth to CPU 4, the sixth through tenth to CPUs 6, 8, 10, 12, and 14 respectively and then start assigning back from the beginning of the list. GOMP_CPU_AFFINITY=0 binds all threads to CPU 0.

There is no libgomp library routine to determine whether a CPU affinity specification is in effect. As a workaround, language-specific library functions, e.g., getenv in C or GET_ENVIRONMENT_VARIABLE in Fortran, may be used to query the setting of the GOMP_CPU_AFFINITY environment variable. A defined CPU affinity on startup cannot be changed or disabled during the runtime of the application.

If both GOMP_CPU_AFFINITY and OMP_PROC_BIND are set, OMP_PROC_BIND has a higher precedence. If neither has been set and OMP_PROC_BIND is unset, or when OMP_PROC_BIND is set to FALSE, the host system will handle the assignment of threads to CPUs.

=item C<GOMP_DEBUG>

Enable debugging output. The variable should be set to 0 (disabled, also the default if not set), or 1 (enabled).

If enabled, some debugging output will be printed during execution. This is currently not specified in more detail, and subject to change.

=item C<GOMP_STACKSIZE>

Determines how long a threads waits actively with consuming CPU power before waiting passively without consuming CPU power. The value may be either INFINITE, INFINITY to always wait actively or an integer which gives the number of spins of the busy-wait loop. The integer may optionally be followed by the following suffixes acting as multiplication factors: k (kilo, thousand), M (mega, million), G (giga, billion), or T (tera, trillion). If undefined, 0 is used when OMP_WAIT_POLICY is PASSIVE, 300,000 is used when OMP_WAIT_POLICY is undefined and 30 billion is used when OMP_WAIT_POLICY is ACTIVE. If there are more OpenMP threads than available CPUs, 1000 and 100 spins are used for OMP_WAIT_POLICY being ACTIVE or undefined, respectively; unless the GOMP_SPINCOUNT is lower or OMP_WAIT_POLICY is PASSIVE.

=item C<GOMP_SPINCOUNT>

Set the default thread stack size in kilobytes. This is different from pthread_attr_get_set_assertstacksize which gets the number of bytes as an argument. If the stack size cannot be set due to system constraints, an error is reported and the initial stack size is left unchanged. If undefined, the stack size is system dependent.

=item C<GOMP_RTEMS_THREAD_POOLS>

This environment variable is only used on the RTEMS real-time operating system. It determines the scheduler instance specific thread pools. The format for GOMP_RTEMS_THREAD_POOLS is a list of optional <thread-pool-count>[$<priority>]@<scheduler-name> configurations separated by : where:

1. C<thread-pool-count> is the thread pool count for this scheduler instance.

2. $<priority> is an optional priority for the worker threads of a thread pool according to pthread_get_set_assertschedparam. In case a priority value is omitted, then a worker thread will inherit the priority of the OpenMP master thread that created it. The priority of the worker thread is not changed after creation, even if a new OpenMP master thread using the worker has a different priority.

3. @<scheduler-name> is the scheduler instance name according to the RTEMS application configuration.

In case no thread pool configuration is specified for a scheduler instance, then each OpenMP master thread of this scheduler instance will use its own dynamically allocated thread pool. To limit the worker thread count of the thread pools, each OpenMP master thread must call set_num_threads.

=back

=head1 SEE ALSO

This module heavily favors the C<GOMP> implementation of the OpenMP
specification within gcc.

L<https://gcc.gnu.org/onlinedocs/libgomp/index.html>

=head1 AUTHOR

A. U. Thor, E<lt>wwlwpd@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2021 by A. U. Thor

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.30.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
