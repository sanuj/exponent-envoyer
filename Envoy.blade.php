@include('config.php')

@setup
$path = '~/'.trim($name, '/');
$date = ( new DateTime )->format('YmdHis');
$env = isset($env) ? $env : "production";
$branch = isset($branch) ? $branch : "master";
$release = $path.'/releases/'.$date;

foreach($servers as $key => $server) {
$servers[$key] = '-i "'.$server['IdentityFile']."\" {$server['User']}@{$server['Hostname']}";
}
@endsetup

@servers($servers)

@task('init')
if [ ! -d {{ $path }}/current ]; then
if [ ! -d {{ $path }} ]; then
mkdir {{ $path }};
fi;
cd {{ $path }};
git clone {{ $repo }} --branch={{ $branch }} --depth=1 -q {{ $release }} ;
echo "Repository cloned";
mv {{ $release }}/storage {{ $path }}/storage;
ln -s {{ $path }}/storage {{ $release }}/storage;
ln -s {{ $path }}/storage/public {{ $release }}/public/storage;
echo "Storage directory set up";
cp {{ $release }}/.env.example {{ $path }}/.env;
ln -s {{ $path }}/.env {{ $release }}/.env;
echo "Environment file set up";
cd {{ $release }};
composer install --no-interaction --quiet --no-dev;
php artisan migrate --env={{ $env }} --force --no-interaction;
ln -s {{ $release }} {{ $path }}/current;
echo "Initial deployment ({{ $date }}) complete";
echo "***You've to configure nginx manually.";
else
echo "Deployment path already initialised (current symlink exists)!";
fi
@endtask

@story('deploy')
deployment:start
deployment:links
deployment:composer
deployment:migrate
deployment:cache
deployment:optimize
deployment:finish
restart:workers
deployment:cleanup
@endstory

@story('restart')
restart:nginx
restart:workers
@endstory

@task('deployment:start')
cd {{ $path }};
echo "Deployment ({{ $date }}) started";
git clone {{ $repo }} --branch={{ $branch }} --depth=1 -q {{ $release }} ;
echo "Repository cloned";
@endtask

@task('deployment:links')
cd {{ $path }};
rm -rf {{ $release }}/storage;
ln -s {{ $path }}/storage {{ $release }}/storage;
echo "Storage directories set up";
ln -s {{ $path }}/.env {{ $release }}/.env;
echo "Environment file set up";
@endtask

@task('deployment:composer')
cd {{ $release }};
composer install --no-interaction --quiet --no-dev;
@endtask

@task('deployment:migrate', ['on' => $run_migrations_on])
cd {{ $release }}

php artisan migrate --env={{ $env }} --force --no-interaction;

cd {{ $path }}
@endtask

@task('deployment:cache')
cd {{ $release }}

php artisan view:clear --quiet;
php artisan cache:clear --quiet;
php artisan config:cache --quiet;
echo 'Cache cleared';

cd {{ $path }}
@endtask

@task('deployment:optimize')
php {{ $release }}/artisan optimize --quiet;
@endtask

@task('deployment:finish')
ln -nfs {{ $release }} {{ $path }}/current;
echo "Deployment ({{ $date }}) finished";
@endtask

@task('deployment:cleanup')
cd {{ $path }}/releases;
find . -maxdepth 1 -name "20*" -mmin +2880 | head -n 5 | xargs rm -Rf;
echo "Cleaned up old deployments";
@endtask

@task('restart:nginx')
sudo service nginx restart;
@endtask

@task('restart:workers')
sudo supervisorctl restart all;
echo "Workers restarted.";
@endtask

@task('exponent:start')
cd {{ $path }}/current;
php artisan exponent:start;
@endtask

@task('exponent:stop')
cd {{ $path }}/current;
php artisan exponent:stop;
@endtask

@task('exponent:import')
@if(!isset($company) or !isset($marketplace) or !isset($filename))
echo 'Syntax: envoy run exponent:import [company] [marketplace] [filename]';
@else
cd {{ $path }}/current;
<?php $temp = '/tmp/'.time().'.csv' ?>
cat >> {{ $temp }} <<'EOF'
{{ file_get_contents($filename) }}
EOF

php artisan exponent:import {{ $company }} {{ $marketplace }} {{ $temp }};
rm {{ $temp }};
@endif
@endtask

@after
@slack($slack, '#dev-bots')
@endafter
