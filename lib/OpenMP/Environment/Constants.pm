package OpenMP::Environment::Constants;
use strict;
use warnings;

use Exporter qw/import/;

our $VERSION = q{1.5.0};

use constant omp_cancellation          => q{OMP_CANCELLATION};
use constant omp_display_env           => q{OMP_DISPLAY_ENV};
use constant omp_default_device        => q{OMP_DEFAULT_DEVICE};
use constant omp_num_teams             => q{OMP_NUM_TEAMS};
use constant omp_dynamic               => q{OMP_DYNAMIC};
use constant omp_max_active_levels     => q{OMP_MAX_ACTIVE_LEVELS};
use constant omp_max_task_priority     => q{OMP_MAX_TASK_PRIORITY};
use constant omp_nested                => q{OMP_NESTED};
use constant omp_num_threads           => q{OMP_NUM_THREADS};
use constant omp_proc_bind             => q{OMP_PROC_BIND};
use constant omp_places                => q{OMP_PLACES};
use constant omp_stacksize             => q{OMP_STACKSIZE};
use constant omp_schedule              => q{OMP_SCHEDULE};
use constant omp_target_offload        => q{OMP_TARGET_OFFLOAD};
use constant omp_thread_limit          => q{OMP_THREAD_LIMIT};
use constant omp_wait_policy           => q{OMP_WAIT_POLICY};
use constant gomp_cpu_affinity         => q{GOMP_CPU_AFFINITY};
use constant gomp_debug                => q{GOMP_DEBUG};
use constant gomp_stacksize            => q{GOMP_STACKSIZE};
use constant gomp_spincount            => q{GOMP_SPINCOUNT};
use constant gomp_rtems_thread_pools   => q{GOMP_RTEMS_THREAD_POOLS};
use constant omp_teams_thread_limit    => q{OMP_TEAMS_THREAD_LIMIT};
use constant omp_allocator             => q{OMP_ALLOCATOR};
use constant omp_affinity_format       => q{OMP_AFFINITY_FORMAT};
use constant omp_display_affinity      => q{OMP_DISPLAY_AFFINITY};

our @CONSTANT_NAMES = qw/
  omp_cancellation omp_display_env omp_default_device omp_num_teams
  omp_dynamic omp_max_active_levels omp_max_task_priority omp_nested
  omp_num_threads omp_proc_bind omp_places omp_stacksize omp_schedule
  omp_target_offload omp_thread_limit omp_wait_policy gomp_cpu_affinity
  gomp_debug gomp_stacksize gomp_spincount gomp_rtems_thread_pools
  omp_teams_thread_limit omp_allocator omp_affinity_format
  omp_display_affinity
/;

our @ENVIRONMENT_NAMES = map { __PACKAGE__->can($_)->() } @CONSTANT_NAMES;
our @EXPORT_OK = @CONSTANT_NAMES;
our %EXPORT_TAGS = ( all => \@CONSTANT_NAMES );

sub constant_names {
    return @CONSTANT_NAMES;
}

sub environment_names {
    return @ENVIRONMENT_NAMES;
}

sub is_environment_name {
    my ($name) = @_;
    return scalar grep { $_ eq $name } @ENVIRONMENT_NAMES;
}

1;

__END__

=pod

=head1 NAME

OpenMP::Environment::Constants - canonical OpenMP and GNU libgomp environment names

=head1 SYNOPSIS

  use OpenMP::Environment::Constants qw/omp_num_threads omp_target_offload/;

  print omp_num_threads;       # OMP_NUM_THREADS
  print omp_target_offload;    # OMP_TARGET_OFFLOAD

=head1 DESCRIPTION

This module defines one Perl constant for each canonical environment variable
supported by L<OpenMP::Environment>.  The lower-case constant names mirror the
public accessor names, while their values are the upper-case environment names.

The constants live in this separate package so that C<OpenMP::Environment> can
retain methods such as C<omp_num_threads> without a subroutine-name collision.
They are normally imported indirectly through the C<:unset>, C<:assert>, or
C<:dsl> tags provided by L<OpenMP::Environment>.

=head1 FUNCTIONS

=head2 constant_names

Returns the lower-case Perl constant names in the stable environment-variable
order used by C<OpenMP::Environment>.

=head2 environment_names

Returns the corresponding canonical C<OMP_*> and C<GOMP_*> names.

=head2 is_environment_name

Returns true when its argument is one of the supported canonical names.

=head1 COPYRIGHT AND LICENSE

Same as Perl.

=for Pod::Coverage omp_cancellation omp_display_env omp_default_device omp_num_teams omp_dynamic omp_max_active_levels omp_max_task_priority omp_nested omp_num_threads omp_proc_bind omp_places omp_stacksize omp_schedule omp_target_offload omp_thread_limit omp_wait_policy gomp_cpu_affinity gomp_debug gomp_stacksize gomp_spincount gomp_rtems_thread_pools omp_teams_thread_limit omp_allocator omp_affinity_format omp_display_affinity

=cut

