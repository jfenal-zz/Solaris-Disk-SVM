use ExtUtils::MakeMaker;

WriteMakefile(
    NAME      => 'Solaris::Disk::SVM',
    PREREQ_PM => {
        'Carp'                  => 0,
        'Term::ANSIColor'       => 0,
        'Solaris::Disk::VTOC'   => 0,
        'Solaris::Disk::Mnttab' => 0,
    },
    PM => {
        map {
            ( "lib/$_.pm" => "\$(INST_LIBDIR)/" . ( split /\// )[-1] . ".pm" )
          }
          qw(
          Solaris/Disk/SVM
          )
    },
    VERSION_FROM   => 'lib/Solaris/Disk/SVM.pm',
    PL_FILES  => {},
    EXE_FILES => ['bin/svm'],
    AUTHOR    => 'Jérôme Fenal <jfenal@free.fr>',
    ABSTRACT  => 'Module to manipulate Solaris Volume Manager (aka. SDS)',
    clean     => { FILES => '*~ */*~ */*/*~ */*/*/*~' },
    dist      => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },

);

