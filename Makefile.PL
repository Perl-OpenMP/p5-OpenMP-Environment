use 5.030000;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'OpenMP::Environment',
    VERSION_FROM      => 'lib/OpenMP/Environment.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ABSTRACT_FROM     => 'lib/OpenMP/Environment.pm', # retrieve abstract from module
    AUTHOR            => 'oodler577',
    LICENSE           => 'perl',
);
