requires 'perl', '5.008001';

on 'configure' => sub {
    requires 'Module::Build::XSUtil', '0';
};

on 'test' => sub {
    requires 'Test2::V0';
    requires 'Test::LeakTrace';
    requires 'Type::Tiny', '2.000000';
};

