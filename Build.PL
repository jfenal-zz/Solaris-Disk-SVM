use Module::Build;
my $build = Module::Build->new(
    module_name  => 'Solaris::Disk::SVM',
    version_from => 'lib/Solaris/Disk/SVM.pm',
    script_files => 'bin/svm',
    license      => 'perl',
    requires     => {
        'perl'                  => '5.6.1', # really ? should check [on] Solaris 8
                                            # default perl version...
        'Carp'                  => 0,
        'Solaris::Disk::Mnttab' => 0,
        'Solaris::Disk::VTOC'   => 0,
        'Term::ANSIColor'       => 0,
    },
    recommends => { 'Test::More' => '0', },
    add_to_cleanup => [ '*~', '*/*~', '*/*/*~', '*/*/*/*~' ],
    gzip           => 'gzip -9f',
);
$build->create_build_script;
