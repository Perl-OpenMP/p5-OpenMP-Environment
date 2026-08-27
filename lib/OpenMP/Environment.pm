package OpenMP::Environment;
use strict;
use warnings;

use Carp qw/croak/;
use Dispatch::Fu qw/dispatch on xdefault/;
use OpenMP::Environment::Constants ();
use OpenMP::Environment::Validation ();

our $VERSION = q{1.5.0};

our @_OMP_VARS = OpenMP::Environment::Constants::environment_names();

# capture state of %ENV
local %ENV = %ENV;

# The DSL is deliberately opt-in.  Constants are installed directly into the
# caller from OpenMP::Environment::Constants so their names never collide with
# the identically named accessor methods in this package.
sub import {
    my ( $pkg, @imports ) = @_;
    return if not @imports;

    my $caller = caller;
    my %export;
    my %constant = map { $_ => 1 } OpenMP::Environment::Constants::constant_names();

    foreach my $item (@imports) {
        if ( $item eq q{:unset} ) {
            $export{unset} = 1;
            $export{$_} = 1 for keys %constant;
        }
        elsif ( $item eq q{:assert} ) {
            $export{assert} = 1;
            $export{$_} = 1 for keys %constant;
        }
        elsif ( $item eq q{:dsl} ) {
            $export{unset} = 1;
            $export{assert} = 1;
            $export{$_} = 1 for keys %constant;
        }
        elsif ( $item eq q{unset} ) {
            $export{unset} = 1;
        }
        elsif ( $item eq q{assert} ) {
            $export{assert} = 1;
        }
        elsif ( $constant{$item} ) {
            $export{$item} = 1;
        }
        else {
            croak qq{"$item" is not exported by OpenMP::Environment};
        }
    }

    no strict q{refs};
    no warnings q{redefine};
    *{"${caller}::unset"} = \&unset if $export{unset};
    *{"${caller}::assert"} = \&assert if $export{assert};
    foreach my $name ( sort keys %constant ) {
        next if not $export{$name};
        *{"${caller}::$name"} = OpenMP::Environment::Constants->can($name);
    }
    return;
}

# constructor
sub new {
    my $pkg = shift;
    my $self = {
        _validation_rules => OpenMP::Environment::Validation::validation_rules(),
    };
    return bless $self, $pkg;
}

# Backward-compatible private validator helpers retained because older callers
# and the regression suite may invoke them directly.
sub _is_ge_if_set {
    my ( $min, $value ) = @_;
    return if not defined $value;
    return q{Value must be an integer great than or equal to 1}
      if $value =~ m/\D/;
    return q{Value must be an integer great than or equal to 1}
      if $value < $min;
    return;
}

sub _is_positive_integer_list_if_set {
    my ($value) = @_;
    return if not defined $value;
    return if $value =~ m/\A\s*[1-9]\d*(?:\s*,\s*[1-9]\d*)*\s*\z/;
    return q{Value must be a comma-separated list of positive integers};
}

sub _no_validate {
    return sub { return undef };
}

sub _is_legacy_false_value {
    my ($value) = @_;
    return 1 if not defined $value;

    # OpenMP environment values are generally allowed surrounding whitespace.
    # Preserve the historical false-value-unsets behavior when that standard
    # spelling is used, including case-insensitive FALSE and numeric zero.
    my $test = $value;
    $test =~ s/\A\s+//;
    $test =~ s/\s+\z//;
    return 1 if not $test;
    return 1 if lc($test) eq q{false};
    return 0;
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

sub print_omp_summary_unset {
    my $self = shift;
    return print $self->_omp_summary_unset;
}

sub _omp_summary_unset {
    my $self  = shift;
    my @lines = ();
    push @lines, qq{Summary of OpenMP Environmental UNSET variables supported in this module:};
  ENV:
    foreach my $ev ( $self->vars_unset ) {
        push @lines, sprintf( qq{%s}, $ev );
    }
    my $ret = join( qq{\n}, @lines );
    $ret .= print qq{\n};
    $ret .= print qq{- none\n} if ( @lines == 1 );
    return $ret;
}

sub print_omp_summary_set {
    my $self = shift;
    return print $self->_omp_summary_set;
}

sub _omp_summary_set {
    my $self  = shift;
    my @lines = ();
    push @lines, qq{Summary of OpenMP Environmental SET variables supported in this module:};
  ENV:
    foreach my $ev_ref ( $self->vars_set ) {
        my $ev  = ( keys %$ev_ref )[0];
        my $val = ( values %$ev_ref )[0];
        push @lines, sprintf( qq{%-25s %s}, $ev, $val );
    }
    my $ret = join( qq{\n}, @lines );
    $ret .= print qq{\n};
    $ret .= print qq{- none\n} if ( @lines == 1 );
    return $ret;
}

sub print_omp_summary {
    my $self = shift;
    return print $self->_omp_summary;
}

sub _omp_summary {
    my $self = shift;
    my $ret  = qq{Summary of OpenMP Environmental ALL variables supported in this module:\n};
    $ret .= sprintf( qq{%-25s %s\n}, q{Variable}, q{Value} );
    $ret .= sprintf( qq{%-25s %s\n}, q{~~~~~~~~}, q{~~~~~} );
  ENV:
    foreach my $ev ( $self->vars ) {
        my $val = ( defined $ENV{$ev} ) ? $ENV{$ev} : q{<XXunsetXX>};
        $ret .= sprintf( qq{%-25s %s\n}, $ev, $val );
    }
    return $ret;
}

# Return a validation-aware lvalue proxy for one environment variable.
# FETCH reads the current value from %ENV; STORE routes assignment back through
# the public accessor so lvalue syntax retains the same validation, filtering,
# and compatibility behavior as traditional setter calls.
sub _lvalue_for :lvalue {
    my ( $self, $ev, $accessor, $has_override, $override ) = @_;
    my $slot;
    tie $slot, q{OpenMP::Environment::_Lvalue},
      $self, $ev, $accessor, $has_override, $override;
    $slot;
}

# OpenMP Environmental Variable setters/getters

sub omp_allocator :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_ALLOCATOR};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_allocator} );
}

sub unset_omp_allocator {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_ALLOCATOR};
    return delete $ENV{$ev};
}

sub omp_affinity_format :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_AFFINITY_FORMAT};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_affinity_format} );
}

sub unset_omp_affinity_format {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_AFFINITY_FORMAT};
    return delete $ENV{$ev};
}

sub omp_display_affinity :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DISPLAY_AFFINITY};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_display_affinity} );
}

sub unset_omp_display_affinity {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DISPLAY_AFFINITY};
    return delete $ENV{$ev};
}

sub omp_cancellation :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_CANCELLATION};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_cancellation} );
}

sub unset_omp_cancellation {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_CANCELLATION};
    return delete $ENV{$ev};
}

sub omp_display_env :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DISPLAY_ENV};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_display_env} );
}

sub unset_omp_display_env {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DISPLAY_ENV};
    return delete $ENV{$ev};
}

sub omp_default_device :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DEFAULT_DEVICE};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_default_device} );
}

sub unset_omp_default_device {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DEFAULT_DEVICE};
    return delete $ENV{$ev};
}

sub omp_dynamic :lvalue {
    my $self = shift;
    my $ev = q{OMP_DYNAMIC};
    my ( $has_override, $override );

    if (@_) {
        my $value = shift;
        my $old = $ENV{$ev};
        if ( _is_legacy_false_value($value) ) {
            $self->unset_omp_dynamic();
            $has_override = 1;
            $override = $old;
        }
        else {
            $self->_get_set_assert( $ev, $value );
        }
    }

    $self->_lvalue_for( $ev, q{omp_dynamic}, $has_override, $override );
}

sub unset_omp_dynamic {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_DYNAMIC};
    return delete $ENV{$ev};
}

sub omp_max_active_levels :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_MAX_ACTIVE_LEVELS};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_max_active_levels} );
}

sub unset_omp_max_active_levels {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_MAX_ACTIVE_LEVELS};
    return delete $ENV{$ev};
}

sub omp_max_task_priority :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_MAX_TASK_PRIORITY};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_max_task_priority} );
}

sub unset_omp_max_task_priority {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_MAX_TASK_PRIORITY};
    return delete $ENV{$ev};
}

sub omp_nested :lvalue {
    my $self = shift;
    my $ev = q{OMP_NESTED};
    my ( $has_override, $override );

    if (@_) {
        my $value = shift;
        my $old = $ENV{$ev};
        if ( _is_legacy_false_value($value) ) {
            $self->unset_omp_nested();
            $has_override = 1;
            $override = $old;
        }
        else {
            $self->_get_set_assert( $ev, $value );
        }
    }

    $self->_lvalue_for( $ev, q{omp_nested}, $has_override, $override );
}

sub unset_omp_nested {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_NESTED};
    return delete $ENV{$ev};
}

sub omp_num_threads :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_NUM_THREADS};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_num_threads} );
}

sub unset_omp_num_threads {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_NUM_THREADS};
    return delete $ENV{$ev};
}

sub omp_num_teams :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_NUM_TEAMS};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_num_teams} );
}

sub unset_omp_num_teams {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_NUM_TEAMS};
    return delete $ENV{$ev};
}

sub omp_proc_bind :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_PROC_BIND};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_proc_bind} );
}

sub unset_omp_proc_bind {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_PROC_BIND};
    return delete $ENV{$ev};
}

sub omp_places :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_PLACES};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_places} );
}

sub unset_omp_places {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_PLACES};
    return delete $ENV{$ev};
}

sub omp_stacksize :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_STACKSIZE};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_stacksize} );
}

sub unset_omp_stacksize {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_STACKSIZE};
    return delete $ENV{$ev};
}

sub omp_schedule :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_SCHEDULE};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_schedule} );
}

sub unset_omp_schedule {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_SCHEDULE};
    return delete $ENV{$ev};
}

sub omp_target_offload :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_TARGET_OFFLOAD};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_target_offload} );
}

sub unset_omp_target_offload {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_TARGET_OFFLOAD};
    return delete $ENV{$ev};
}

sub omp_thread_limit :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_THREAD_LIMIT};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_thread_limit} );
}

sub unset_omp_thread_limit {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_THREAD_LIMIT};
    return delete $ENV{$ev};
}

sub omp_teams_thread_limit :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_TEAMS_THREAD_LIMIT};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_teams_thread_limit} );
}

sub unset_omp_teams_thread_limit {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_TEAMS_THREAD_LIMIT};
    return delete $ENV{$ev};
}

sub omp_wait_policy :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_WAIT_POLICY};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{omp_wait_policy} );
}

sub unset_omp_wait_policy {
    my ( $self, $value ) = @_;
    my $ev = q{OMP_WAIT_POLICY};
    return delete $ENV{$ev};
}

sub gomp_cpu_affinity :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_CPU_AFFINITY};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{gomp_cpu_affinity} );
}

sub unset_gomp_cpu_affinity {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_CPU_AFFINITY};
    return delete $ENV{$ev};
}

sub gomp_debug :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_DEBUG};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{gomp_debug} );
}

sub unset_gomp_debug {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_DEBUG};
    return delete $ENV{$ev};
}

sub gomp_stacksize :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_STACKSIZE};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{gomp_stacksize} );
}

sub unset_gomp_stacksize {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_STACKSIZE};
    return delete $ENV{$ev};
}

sub gomp_spincount :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_SPINCOUNT};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{gomp_spincount} );
}

sub unset_gomp_spincount {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_SPINCOUNT};
    return delete $ENV{$ev};
}

sub gomp_rtems_thread_pools :lvalue {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_RTEMS_THREAD_POOLS};
    $self->_get_set_assert( $ev, $value );
    $self->_lvalue_for( $ev, q{gomp_rtems_thread_pools} );
}

sub unset_gomp_rtems_thread_pools {
    my ( $self, $value ) = @_;
    my $ev = q{GOMP_RTEMS_THREAD_POOLS};
    return delete $ENV{$ev};
}

# Functional DSL operations.  Dispatch::Fu supplies a static whitelist: an
# arbitrary environment-variable string cannot be deleted or asserted through
# these functions unless it is one of the 25 canonical constants.
sub _unset_case {
    my ($ev) = @_;
    return delete $ENV{$ev};
}

sub _assert_case {
    my ($ev) = @_;
    return OpenMP::Environment::Validation::assert_variable( \%ENV, $ev );
}

sub unset($) {
    my ($ev) = @_;
    return dispatch {
        xdefault shift;
    }
    $ev,
      on default                   => sub { croak qq{Unsupported OpenMP/libgomp environment variable "$ev"} },
      on q{OMP_CANCELLATION}       => \&_unset_case,
      on q{OMP_DISPLAY_ENV}        => \&_unset_case,
      on q{OMP_DEFAULT_DEVICE}     => \&_unset_case,
      on q{OMP_NUM_TEAMS}          => \&_unset_case,
      on q{OMP_DYNAMIC}            => \&_unset_case,
      on q{OMP_MAX_ACTIVE_LEVELS}  => \&_unset_case,
      on q{OMP_MAX_TASK_PRIORITY}  => \&_unset_case,
      on q{OMP_NESTED}             => \&_unset_case,
      on q{OMP_NUM_THREADS}        => \&_unset_case,
      on q{OMP_PROC_BIND}          => \&_unset_case,
      on q{OMP_PLACES}             => \&_unset_case,
      on q{OMP_STACKSIZE}          => \&_unset_case,
      on q{OMP_SCHEDULE}           => \&_unset_case,
      on q{OMP_TARGET_OFFLOAD}     => \&_unset_case,
      on q{OMP_THREAD_LIMIT}       => \&_unset_case,
      on q{OMP_WAIT_POLICY}        => \&_unset_case,
      on q{GOMP_CPU_AFFINITY}      => \&_unset_case,
      on q{GOMP_DEBUG}             => \&_unset_case,
      on q{GOMP_STACKSIZE}         => \&_unset_case,
      on q{GOMP_SPINCOUNT}         => \&_unset_case,
      on q{GOMP_RTEMS_THREAD_POOLS} => \&_unset_case,
      on q{OMP_TEAMS_THREAD_LIMIT} => \&_unset_case,
      on q{OMP_ALLOCATOR}          => \&_unset_case,
      on q{OMP_AFFINITY_FORMAT}    => \&_unset_case,
      on q{OMP_DISPLAY_AFFINITY}   => \&_unset_case;
}

sub assert($) {
    my ($ev) = @_;
    return dispatch {
        xdefault shift;
    }
    $ev,
      on default                   => sub { croak qq{Unsupported OpenMP/libgomp environment variable "$ev"} },
      on q{OMP_CANCELLATION}       => \&_assert_case,
      on q{OMP_DISPLAY_ENV}        => \&_assert_case,
      on q{OMP_DEFAULT_DEVICE}     => \&_assert_case,
      on q{OMP_NUM_TEAMS}          => \&_assert_case,
      on q{OMP_DYNAMIC}            => \&_assert_case,
      on q{OMP_MAX_ACTIVE_LEVELS}  => \&_assert_case,
      on q{OMP_MAX_TASK_PRIORITY}  => \&_assert_case,
      on q{OMP_NESTED}             => \&_assert_case,
      on q{OMP_NUM_THREADS}        => \&_assert_case,
      on q{OMP_PROC_BIND}          => \&_assert_case,
      on q{OMP_PLACES}             => \&_assert_case,
      on q{OMP_STACKSIZE}          => \&_assert_case,
      on q{OMP_SCHEDULE}           => \&_assert_case,
      on q{OMP_TARGET_OFFLOAD}     => \&_assert_case,
      on q{OMP_THREAD_LIMIT}       => \&_assert_case,
      on q{OMP_WAIT_POLICY}        => \&_assert_case,
      on q{GOMP_CPU_AFFINITY}      => \&_assert_case,
      on q{GOMP_DEBUG}             => \&_assert_case,
      on q{GOMP_STACKSIZE}         => \&_assert_case,
      on q{GOMP_SPINCOUNT}         => \&_assert_case,
      on q{GOMP_RTEMS_THREAD_POOLS} => \&_assert_case,
      on q{OMP_TEAMS_THREAD_LIMIT} => \&_assert_case,
      on q{OMP_ALLOCATOR}          => \&_assert_case,
      on q{OMP_AFFINITY_FORMAT}    => \&_assert_case,
      on q{OMP_DISPLAY_AFFINITY}   => \&_assert_case;
}

# used to assert valid environment, useful if variables are already set externally
sub assert_omp_environment {
    return OpenMP::Environment::Validation::assert_environment( \%ENV );
}

sub _get_set_assert {
    my ( $self, $ev, $value ) = @_;
    if ( defined $value ) {
        my $filtered_value = $self->_assert_valid( $ev, $value );
        $ENV{$ev} = $filtered_value;
    }
    return ( exists $ENV{$ev} ) ? $ENV{$ev} : undef;
}

sub _assert_valid {
    my ( $self, $ev, $value ) = @_;
    return OpenMP::Environment::Validation::validate_assignment( $ev, $value );
}

package OpenMP::Environment::_Lvalue;

use strict;
use warnings;

sub TIESCALAR {
    my ( $class, $owner, $ev, $accessor, $has_override, $override ) = @_;
    return bless {
        owner        => $owner,
        ev           => $ev,
        accessor     => $accessor,
        has_override => $has_override,
        override     => $override,
    }, $class;
}

sub FETCH {
    my $self = shift;
    return $self->{override} if $self->{has_override};
    return $ENV{ $self->{ev} };
}

sub STORE {
    my ( $self, $value ) = @_;
    my $owner    = $self->{owner};
    my $accessor = $self->{accessor};
    $owner->$accessor($value);
    return;
}

package OpenMP::Environment;

1;

__END__

=head1 NAME

OpenMP::Environment - manage OpenMP and GNU libgomp environment variables from Perl

=head1 SYNOPSIS

C<OpenMP::Environment> is intended for two closely related jobs:

=over 4

=item *

Preparing C<%ENV> before launching an external executable compiled with OpenMP.

=item *

Managing the Perl-side OpenMP environment used with L<OpenMP::Simple> and
OpenMP-enabled C code loaded into a Perl process.

=back

=head2 Launching an external OpenMP executable

An external executable reads its OpenMP environment when the process starts,
which makes this the most direct use of C<OpenMP::Environment>:

  use strict;
  use warnings;

  use OpenMP::Environment;

  my $env = OpenMP::Environment->new;
  my $program = q{/path/to/my-openmp-program};

  for my $threads ( 1, 2, 4, 8, 16 ) {
      $env->omp_num_threads = $threads;
      $env->omp_proc_bind   = q{CLOSE};
      $env->omp_places      = q{cores};

      # Optional guard before starting the child process.
      $env->assert_omp_environment;

      my $status = system { $program } $program, q{--input}, q{data.in};
      die qq{$program failed: status=$status\n} if $status != 0;
  }

Every C<system>, C<exec>, IPC, scheduler, or similar child-process launch
inherits the current C<%ENV> unless the caller deliberately replaces it.
This makes the module useful for benchmark drivers, parameter sweeps, test
harnesses, HPC launcher scripts, and production workflows around OpenMP
executables.

=head2 Using OpenMP::Environment with OpenMP::Simple

L<OpenMP::Simple> provides C macros that re-read selected values from C<%ENV>
and apply them through OpenMP runtime setter functions. This is useful because
an OpenMP runtime linked into a shared library is normally initialized once,
when that library is loaded into the Perl process.

  use strict;
  use warnings;

  use OpenMP::Simple;
  use OpenMP::Environment;

  use Inline (
      C    => 'DATA',
      with => qw/OpenMP::Simple/,
  );

  my $env = OpenMP::Environment->new;

  for my $want_num_threads ( 1 .. 8 ) {
      $env->omp_num_threads = $want_num_threads;
      $env->assert_omp_environment;

      my $got_num_threads = _check_num_threads();
      printf "%d threads spawned; expected %d\n",
          $got_num_threads, $want_num_threads;
  }

  __DATA__
  __C__

  int _check_num_threads() {
      int ret = 0;

      PerlOMP_UPDATE_WITH_ENV__NUM_THREADS

      #pragma omp parallel
      {
          #pragma omp single
          ret = omp_get_num_threads();
      }

      return ret;
  }

The runtime-update macros in L<OpenMP::Simple> only apply to OpenMP settings
for which a corresponding runtime setter exists. Settings that are only read
at OpenMP runtime initialization still need to be established before the
OpenMP-enabled shared library is loaded.

=head2 OpenMP 5.x examples

C<OMP_NUM_THREADS> may be a comma-separated list for nested parallel levels.
Version 1.5.0 accepts this standard form in addition to the single integer
form accepted by earlier releases:

  $env->omp_num_threads = q{8,4,2};

GCC libgomp also supports affinity-display controls introduced in OpenMP 5.0:

  $env->omp_display_affinity = q{true};
  $env->omp_affinity_format  = q{thread %n affinity %A};

And the OpenMP default allocator may be selected through C<OMP_ALLOCATOR>:

  $env->omp_allocator = q{omp_high_bw_mem_alloc};

Ordinary assignment to C<OMP_ALLOCATOR> and C<OMP_AFFINITY_FORMAT> remains
pass-through for backward compatibility with releases that did not validate
those grammars.  The C<assert> DSL, C<assert_omp_environment>, and
L<OpenMP::Environment::Validation> provide strict portable/libgomp grammar
validation when requested.

=head2 Assertion and unset DSL

Because C<%ENV> is process-global, version 1.5.0 adds an opt-in functional DSL
for operations that do not need object-local state:

  use OpenMP::Environment qw/:dsl/;

  my $env = OpenMP::Environment->new;
  $env->omp_num_threads = 16;
  $env->omp_schedule    = q{dynamic,4};

  assert omp_num_threads;
  assert omp_schedule;

  unset omp_schedule;
  unset omp_num_threads;

The constants are imported only when requested.  Existing callers that simply
say C<use OpenMP::Environment;> receive no new symbols.

C<:unset> imports C<unset> plus all environment constants, C<:assert> imports
C<assert> plus the constants, and C<:dsl> imports both functions plus the
constants.  Individual symbols can also be requested explicitly:

  use OpenMP::Environment qw/unset omp_target_offload/;

  unset omp_target_offload;

The constants live in L<OpenMP::Environment::Constants> so lower-case names
such as C<omp_num_threads> do not collide with the accessor methods of the same
name in this package.

=head1 DESCRIPTION

C<OpenMP::Environment> provides lvalue-capable getter/setter methods and
explicit unsetters for the OpenMP and GNU libgomp environment variables
documented by GCC 16.2.0. The module changes C<%ENV>; it does not implement
OpenMP itself.

GCC 16.2.0 reports C<_OPENMP=202111>, corresponding to OpenMP 5.2. The
GCC/libgomp B<OpenMP Environment Variables> chapter lists 25 C<OMP_*> and
C<GOMP_*> variables, and this release exposes that complete 25-variable libgomp
set while retaining the accessors and semantics from earlier
C<OpenMP::Environment> releases.

OpenMP 5.2 itself defines additional tool/debugging environment variables,
including C<OMP_TOOL>, C<OMP_TOOL_LIBRARIES>, C<OMP_TOOL_VERBOSE_INIT>, and
C<OMP_DEBUG>.  They are not part of libgomp's 25-variable environment chapter
and are outside the API scope of this release; the phrase "all 25" in this
document always means the 25 variables listed by libgomp, not every environment
variable appearing anywhere in OpenMP 5.2.

The current API supports:

=over 4

=item * C<OMP_ALLOCATOR>

=item * C<OMP_AFFINITY_FORMAT>

=item * C<OMP_DISPLAY_AFFINITY>

=item * comma-separated positive-integer lists for C<OMP_NUM_THREADS>

=item * lvalue assignment for all C<omp_*> and C<gomp_*> accessors, routed through the same compatibility validation policy as traditional setters

=back

The GNU libgomp manual for GCC 16.2.0 is the implementation reference for this
module:

L<https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/>

=head1 GCC 16.2 AND DEVICE-SPECIFIC ENVIRONMENT FORMS

OpenMP 5.1 added device-specific forms for many environment variables that
set internal control variables. GCC 16.2 libgomp recognizes applicable forms
such as:

  OMP_NUM_THREADS=8
  OMP_NUM_THREADS_DEV=4
  OMP_NUM_THREADS_DEV_0=2
  OMP_NUM_THREADS_ALL=1

The named methods in this module deliberately continue to represent the
canonical variable names, preserving the existing API. Device-specific forms
can be placed directly in C<%ENV> when needed. C<assert_omp_environment> and
the summary methods operate on the canonical variables exposed by C<vars>.

This distinction is especially useful for external executable launchers: set
the device-specific form directly in C<%ENV>, use the normal accessors for the
host/canonical values, then start the OpenMP executable.

=head1 VALIDATION

Version 1.5.0 moves validation policy into
L<OpenMP::Environment::Validation>.  That module documents the OpenMP 5.2 rule,
the GCC 16.2/libgomp interpretation or extension, valid and invalid examples,
and the implementation-defined areas for each supported variable.

There are deliberately two validation modes so existing programs are not
broken.

=head2 Assignment compatibility

Traditional setters and lvalue assignment retain every value and behavior
accepted by the pre-1.5.0 validation contract.  Variables that were already
validated continue to be validated and normalized.  Version 1.5.0 additionally
recognizes the OpenMP rule that surrounding whitespace is permitted for OpenMP
environment values (except C<OMP_AFFINITY_FORMAT>, where whitespace is
significant).  Variables that historically accepted arbitrary strings continue
to accept them on assignment:

  $env->gomp_spincount = q{legacy application value};

This preserves existing code and is especially important because earlier
releases explicitly documented several complex grammars as pass-through.

=head2 Strict assertion

The new C<assert> DSL and the existing C<assert_omp_environment> method use the
strict validation engine for all 25 variables listed in GCC/libgomp's OpenMP
environment-variable chapter:

  use OpenMP::Environment qw/:assert/;

  $ENV{OMP_SCHEDULE} = q{nonmonotonic:dynamic,4};
  assert omp_schedule;

  $env->assert_omp_environment;

Strict validation covers complex grammars including C<OMP_PROC_BIND>,
C<OMP_PLACES>, C<OMP_SCHEDULE>, C<OMP_STACKSIZE>, C<OMP_ALLOCATOR>,
C<OMP_AFFINITY_FORMAT>, and the GNU C<GOMP_*> extensions.

It also detects portable cross-variable conditions that OpenMP explicitly
classifies as implementation-defined.  In particular:

  OMP_NESTED=FALSE
  OMP_MAX_ACTIVE_LEVELS=4

is reported as a conflict.  Non-conflicting relationships, such as
C<OMP_PROC_BIND> taking precedence over C<GOMP_CPU_AFFINITY> in libgomp, are
available through the machine-readable analysis API in
L<OpenMP::Environment::Validation>.

=head2 No system probing

Validation is intentionally system-agnostic.  It does not inspect processors,
NUMA topology, GPUs, target devices, allocator availability, runtime state,
C</proc>, hwloc, compiler executables, or operating-system resources.  A value
can therefore be syntactically valid while depending on runtime resources:

  OMP_DEFAULT_DEVICE=7
  OMP_PLACES={0,1,2,3}
  OMP_STACKSIZE=64G

See L<OpenMP::Environment::Validation> for the detailed human- and
machine-readable validation reference.

=head1 METHODS

=head2 Construction and inspection

=over 4

=item C<new>

  my $env = OpenMP::Environment->new;

Creates a new environment manager.

=item C<vars>

Returns the canonical C<OMP_*> and C<GOMP_*> variable names supported by this
release. Existing variable ordering from version 1.2.3 is retained, with new
GCC 16.2 variables appended for compatibility.

=item C<vars_set>

Returns hash references for supported variables currently considered set.

=item C<vars_unset>

Returns supported variables currently considered unset.

=item C<assert_omp_environment>

Strictly validates supported canonical variables already set in C<%ENV>,
including the complex grammars introduced in the 1.5.0 validation module and
portable cross-variable conflicts. Dies on the first validation failure or
conflict and returns true when validation succeeds.

=item C<print_omp_summary>

Prints all supported canonical variables and their current values or unset
status.

=item C<print_omp_summary_set>

Prints supported canonical variables currently set.

=item C<print_omp_summary_unset>

Prints supported canonical variables currently unset.

=back

=head2 Functional DSL

=over 4

=item C<unset CONSTANT>

  use OpenMP::Environment qw/:unset/;

  $env->omp_target_offload = q{MANDATORY};
  unset omp_target_offload;

Deletes one supported environment variable through a static L<Dispatch::Fu>
dispatch table and returns the previous value, matching Perl C<delete>
semantics.  Unsupported names are rejected.

=item C<assert CONSTANT>

  use OpenMP::Environment qw/:assert/;

  $ENV{OMP_SCHEDULE} = q{dynamic,4};
  assert omp_schedule;

Strictly validates the selected supported variable and any portable
cross-variable conflict involving it.  An unset supported variable is valid.

=back

=head2 Environment-variable accessors

Each C<omp_*> or C<gomp_*> method is an lvalue-capable getter/setter. New code
may use normal Perl assignment syntax, which is the preferred form in this
documentation:

  $env->omp_num_threads = 8;
  $env->omp_proc_bind   = q{spread};
  $env->omp_places      = q{cores};

Lvalue assignment uses the same validation and filtering as the traditional
setter form. Compound operations therefore also pass their resulting value
through the accessor:

  $env->omp_num_threads++;
  $env->gomp_spincount += 1000;
  $env->omp_affinity_format .= q{ %n};

Invalid lvalue assignments die without replacing the previous valid value.

=head3 Traditional getter/setter usage

The pre-1.4.0 call-style API remains fully supported for backward
compatibility. Existing code does not need to change:

  $env->omp_num_threads(8);          # traditional setter
  my $threads = $env->omp_num_threads();  # traditional getter
  $env->unset_omp_num_threads();     # explicit unsetter

The corresponding C<unset_*> method deletes the variable and returns its
previous value, following Perl's normal C<delete> semantics.

For C<OMP_DYNAMIC> and C<OMP_NESTED>, the historical behavior is retained in
both forms: assigning or passing a false value unsets the environment variable.

=over 4

=item C<omp_allocator([$value])>

Getter/setter for C<OMP_ALLOCATOR>. Assignment remains pass-through for backward compatibility; strict C<assert> validates allocator/memory-space/trait grammar.

=item C<unset_omp_allocator>

Deletes C<OMP_ALLOCATOR>.

=item C<omp_affinity_format([$value])>

Getter/setter for C<OMP_AFFINITY_FORMAT>. Assignment remains pass-through for backward compatibility; strict C<assert> validates affinity-format field syntax.

=item C<unset_omp_affinity_format>

Deletes C<OMP_AFFINITY_FORMAT>.

=item C<omp_cancellation([$value])>

Getter/setter for C<OMP_CANCELLATION>. Accepts C<TRUE> or C<FALSE>,
case-insensitively.

=item C<unset_omp_cancellation>

Deletes C<OMP_CANCELLATION>.

=item C<omp_display_affinity([$value])>

Getter/setter for C<OMP_DISPLAY_AFFINITY>. Accepts C<TRUE> or C<FALSE>,
case-insensitively.

=item C<unset_omp_display_affinity>

Deletes C<OMP_DISPLAY_AFFINITY>.

=item C<omp_display_env([$value])>

Getter/setter for C<OMP_DISPLAY_ENV>. Accepts C<TRUE>, C<FALSE>, or C<VERBOSE>,
case-insensitively.

=item C<unset_omp_display_env>

Deletes C<OMP_DISPLAY_ENV>.

=item C<omp_default_device([$value])>

Getter/setter for C<OMP_DEFAULT_DEVICE>. Validated as a non-negative integer.

=item C<unset_omp_default_device>

Deletes C<OMP_DEFAULT_DEVICE>.

=item C<omp_dynamic([$value])>

Getter/setter for C<OMP_DYNAMIC>. Existing compatibility behavior is retained: a false value (C<0>, C<false>,
or C<FALSE>) unsets C<OMP_DYNAMIC> rather than storing a false string. Calling
the method with no value is a normal, non-destructive getter.

=item C<unset_omp_dynamic>

Deletes C<OMP_DYNAMIC>.

=item C<omp_max_active_levels([$value])>

Getter/setter for C<OMP_MAX_ACTIVE_LEVELS>.  GCC/libgomp documents a positive
integer and this module preserves that GNU/legacy rule.  OpenMP 5.2 itself
permits a non-negative integer, so zero is OpenMP-valid but is rejected by this
GCC/libgomp-oriented validation profile.

=item C<unset_omp_max_active_levels>

Deletes C<OMP_MAX_ACTIVE_LEVELS>.

=item C<omp_max_task_priority([$value])>

Getter/setter for C<OMP_MAX_TASK_PRIORITY>. Validated as a non-negative integer.

=item C<unset_omp_max_task_priority>

Deletes C<OMP_MAX_TASK_PRIORITY>.

=item C<omp_nested([$value])>

Getter/setter for the deprecated-but-still-supported C<OMP_NESTED> variable.
Existing compatibility behavior is retained: a false value unsets the variable.
Calling the method with no value is a normal, non-destructive getter. For new
code, C<OMP_MAX_ACTIVE_LEVELS> is generally preferable.

=item C<unset_omp_nested>

Deletes C<OMP_NESTED>.

=item C<omp_num_teams([$value])>

Getter/setter for C<OMP_NUM_TEAMS>. Validated as a positive integer.

=item C<unset_omp_num_teams>

Deletes C<OMP_NUM_TEAMS>.

=item C<omp_num_threads([$value])>

Getter/setter for C<OMP_NUM_THREADS>. Accepts either one positive integer or a
comma-separated list of positive integers such as C<8,4,2>.

=item C<unset_omp_num_threads>

Deletes C<OMP_NUM_THREADS>.

=item C<omp_proc_bind([$value])>

Getter/setter for C<OMP_PROC_BIND>. Assignment remains pass-through for backward compatibility; strict C<assert> validates OpenMP policies plus libgomp's deprecated C<MASTER> compatibility spelling.

=item C<unset_omp_proc_bind>

Deletes C<OMP_PROC_BIND>.

=item C<omp_places([$value])>

Getter/setter for C<OMP_PLACES>. Assignment remains pass-through for backward compatibility; strict C<assert> validates grammar without probing processor topology.

=item C<unset_omp_places>

Deletes C<OMP_PLACES>.

=item C<omp_stacksize([$value])>

Getter/setter for C<OMP_STACKSIZE>. Assignment remains pass-through for backward compatibility; strict C<assert> validates positive size/unit syntax without checking memory availability.

=item C<unset_omp_stacksize>

Deletes C<OMP_STACKSIZE>.

=item C<omp_schedule([$value])>

Getter/setter for C<OMP_SCHEDULE>. Assignment remains pass-through for backward compatibility; strict C<assert> validates the OpenMP 5.2 C<[modifier:]kind[,chunk]> grammar.

=item C<unset_omp_schedule>

Deletes C<OMP_SCHEDULE>.

=item C<omp_target_offload([$value])>

Getter/setter for C<OMP_TARGET_OFFLOAD>. Accepts C<MANDATORY>, C<DISABLED>, or
C<DEFAULT>, case-insensitively.

=item C<unset_omp_target_offload>

Deletes C<OMP_TARGET_OFFLOAD>.

=item C<omp_teams_thread_limit([$value])>

Getter/setter for C<OMP_TEAMS_THREAD_LIMIT>. Validated as a positive integer.

=item C<unset_omp_teams_thread_limit>

Deletes C<OMP_TEAMS_THREAD_LIMIT>.

=item C<omp_thread_limit([$value])>

Getter/setter for C<OMP_THREAD_LIMIT>. Validated as a positive integer.

=item C<unset_omp_thread_limit>

Deletes C<OMP_THREAD_LIMIT>.

=item C<omp_wait_policy([$value])>

Getter/setter for C<OMP_WAIT_POLICY>. Accepts C<ACTIVE> or C<PASSIVE>,
case-insensitively.

=item C<unset_omp_wait_policy>

Deletes C<OMP_WAIT_POLICY>.

=item C<gomp_cpu_affinity([$value])>

Getter/setter for GNU C<GOMP_CPU_AFFINITY>. Assignment remains pass-through for backward compatibility; strict C<assert> validates GNU CPU/range/stride syntax without checking host CPUs.

=item C<unset_gomp_cpu_affinity>

Deletes C<GOMP_CPU_AFFINITY>.

=item C<gomp_debug([$value])>

Getter/setter for GNU C<GOMP_DEBUG>. Accepts C<0> or C<1>.

=item C<unset_gomp_debug>

Deletes C<GOMP_DEBUG>.

=item C<gomp_stacksize([$value])>

Getter/setter for GNU C<GOMP_STACKSIZE>, which controls the default worker
thread stack size in kilobytes. Assignment remains pass-through; strict
C<assert> validates GNU numeric syntax plus the historical unit-suffix
compatibility accepted by this module.

=item C<unset_gomp_stacksize>

Deletes C<GOMP_STACKSIZE>.

=item C<gomp_spincount([$value])>

Getter/setter for GNU C<GOMP_SPINCOUNT>, which controls active busy-waiting
before passive waiting. Assignment remains pass-through for backward
compatibility; strict C<assert> accepts an integer with documented magnitude
suffixes or C<INFINITE>/C<INFINITY>.

=item C<unset_gomp_spincount>

Deletes C<GOMP_SPINCOUNT>.

=item C<gomp_rtems_thread_pools([$value])>

Getter/setter for GNU C<GOMP_RTEMS_THREAD_POOLS>, used only on RTEMS.
Assignment remains pass-through for backward compatibility; strict C<assert>
validates the GNU C<count[$priority]@scheduler> list grammar without probing
RTEMS.

=item C<unset_gomp_rtems_thread_pools>

Deletes C<GOMP_RTEMS_THREAD_POOLS>.

=back

=head1 SUPPORTED ENVIRONMENT VARIABLES

The canonical list in GCC 16.2 libgomp is:

  OMP_ALLOCATOR
  OMP_AFFINITY_FORMAT
  OMP_CANCELLATION
  OMP_DISPLAY_AFFINITY
  OMP_DISPLAY_ENV
  OMP_DEFAULT_DEVICE
  OMP_DYNAMIC
  OMP_MAX_ACTIVE_LEVELS
  OMP_MAX_TASK_PRIORITY
  OMP_NESTED
  OMP_NUM_TEAMS
  OMP_NUM_THREADS
  OMP_PROC_BIND
  OMP_PLACES
  OMP_STACKSIZE
  OMP_SCHEDULE
  OMP_TARGET_OFFLOAD
  OMP_TEAMS_THREAD_LIMIT
  OMP_THREAD_LIMIT
  OMP_WAIT_POLICY
  GOMP_CPU_AFFINITY
  GOMP_DEBUG
  GOMP_STACKSIZE
  GOMP_SPINCOUNT
  GOMP_RTEMS_THREAD_POOLS

For authoritative grammar, defaults, ICV scope, and implementation notes, see
the GCC 16.2 libgomp environment-variable chapter:

L<https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/Environment-Variables.html>

=head1 EXTERNAL EXECUTABLES VS. IN-PROCESS OPENMP

For an external OpenMP executable, environment changes made immediately before
C<system> or C<exec> naturally affect the new process. This is the simplest and
most general usage of the module.

For OpenMP-enabled C code loaded into the current Perl process through XS,
L<Inline::C>, or another FFI mechanism, the OpenMP runtime may already have read
its initialization environment. L<OpenMP::Simple> addresses the useful subset
of settings that can be refreshed through OpenMP runtime setter APIs.

This means the two modules complement each other:

  OpenMP::Environment  -> manages and validates %ENV
  OpenMP::Simple       -> applies selected %ENV values to an active runtime

=head1 EXAMPLES IN THE DISTRIBUTION

The C<examples/> directory contains launcher, environment-summary, validation,
and Inline::C/OpenMP examples. The launcher example is particularly relevant
when wrapping existing OpenMP-enabled applications.

=head1 BACKWARD COMPATIBILITY

Version 1.5.0 remains an additive update. Existing accessor names remain
unchanged. Existing false/unset behavior for C<OMP_DYNAMIC> and C<OMP_NESTED>
is preserved. Their no-argument calls now behave as non-destructive getters,
consistent with every other accessor. Existing canonical variable ordering
returned by C<vars> is preserved, with the three newly supported GCC 16.2
variables appended.

Every assignment accepted by previous releases remains accepted.  The strict
1.5.0 validation rules for historically pass-through variables are opt-in via
C<assert>, C<assert_omp_environment>, or L<OpenMP::Environment::Validation>.
Thus validation can be substantially more informative without changing setter
or lvalue compatibility.

=head1 SEE ALSO

L<OpenMP::Environment::Constants>, L<OpenMP::Environment::Validation>,
L<Dispatch::Fu>, L<OpenMP::Simple>, L<Inline::C>, and the GCC libgomp manual:

L<https://gcc.gnu.org/onlinedocs/gcc-16.2.0/libgomp/>

The OpenMP specification is available from L<https://www.openmp.org/>.

=head1 AUTHOR

Brett Estrade L<< <oodler@cpan.org> >>

=head1 ACKNOWLEDGEMENTS

Thanks to the Perl and OpenMP communities, including contributors and
participants in the Perl C<#pdl> and C<#native> channels who helped with
Inline::C, shared-library load-time, and OpenMP-runtime behavior discussions.

=head1 COPYRIGHT AND LICENSE

Same as Perl.

=for Pod::Coverage _assert_valid _get_set_assert _lvalue_for _is_ge_if_set _is_positive_integer_list_if_set _no_validate _omp_summary _omp_summary_set _omp_summary_unset _unset_case _assert_case import unset assert TIESCALAR FETCH STORE

