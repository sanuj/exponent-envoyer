<?php
// Project Name: Creates a deployment directory in home directory.
$name = 'exponent';

// Repository!
$repo = 'git@github.com:sanuj/price-manager.git';

// Application Servers.
$servers = [
    'app1' => [
        'Hostname' => '52.38.186.26',
        'User' => 'ubuntu',
        'IdentityFile' => __DIR__.'/keys/app1.pem',
    ],
];
// Database config.
$run_migrations_on = ['app1'];

$slack = 'https://hooks.slack.com/services/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';
