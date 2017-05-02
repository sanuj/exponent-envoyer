#!/usr/bin/env bash
# => Variables
# ----------------------------------------------------------------
USER=ubuntu
SUDO_PASSWORD=kjlasiu3o12389co31u98djbaiue2 #prompt
SERVER=exponent-app-1
PROJECT=exponent

# => Change root password.
# ----------------------------------------------------------------
# echo "root:${SUDO_PASSWORD}" | chpasswd

# => Oh! IPv6? Got you.
# ----------------------------------------------------------------
sudo sed -i "s/#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/" /etc/gai.conf

# => Fix locale!
# ----------------------------------------------------------------
locale-gen en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
cat >> /etc/environment << EOF
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
EOF

# => Upgrade base packages.
# ----------------------------------------------------------------
echo 'Upgrade all packages'
apt-get update
apt-get upgrade -y
apt-get install -y --force-yes software-properties-common

# => Add a few PPAs to stay current.
# ----------------------------------------------------------------
echo 'Add PPA Nginx!'
apt-add-repository ppa:nginx/development -y 2> /dev/null
echo 'Add PPA Redis!'
apt-add-repository ppa:chris-lea/redis-server -y 2> /dev/null
echo 'Add PPA PHP!'
apt-add-repository ppa:ondrej/php -y 2> /dev/null

# => Update package lists.
# ----------------------------------------------------------------
apt-get update
echo 'PPAs added!';

# => Install base packages.
# ----------------------------------------------------------------
echo 'Installing: build-essential curl  fail2ban gcc git libmcrypt4 libpcre3-dev make python2.7 python-pip supervisor ufw unattended-upgrades unzip whois zsh'
apt-get install -y --allow-unauthenticated build-essential curl  fail2ban gcc git libmcrypt4 libpcre3-dev \
    make python2.7 python-pip supervisor ufw unattended-upgrades unzip whois zsh

# => Disable password authentication over SSH
# ----------------------------------------------------------------
sed -i -e 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sed -i -e 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config

# => Enforce SHH Protocol 2
# ----------------------------------------------------------------
sed -i -e 's/#Protocol 2/Protocol 2/g' /etc/ssh/sshd_config
sed -i -e 's/#LoginGraceTime 2m/LoginGraceTime 2m/g' /etc/ssh/sshd_config
sed -i -e 's/#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
ssh-keygen -A
service ssh restart

# => Configure hostname
# ----------------------------------------------------------------
echo "${SERVER}" > /etc/hostname
sed -i "s/127\.0\.0\.1.*localhost/127.0.0.1	${SERVER} localhost/" /etc/hosts
hostname "${SERVER}"

# => Set timezone
# ----------------------------------------------------------------
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime

# => Configure SSH access for ${USER}
# ----------------------------------------------------------------
if [ ! -d /root/.ssh ]
then
  mkdir -p /root/.ssh
  touch /root/.ssh/authorized_keys
fi

if ! [ $(id -u ${USER} 2> /dev/null) ] ; then
    useradd '{{ $user }}'
fi

mkdir -p /home/${USER}/.ssh
mkdir -p /home/${USER}/.zero
adduser ${USER} sudo # Already done with cloud config.

chsh -s /bin/bash ${USER}
cp /root/.profile /home/${USER}/.profile
cp /root/.bashrc /home/${USER}/.bashrc

# Generate server SSH key.
ssh-keygen -f /home/${USER}/.ssh/id_rsa -t rsa -N ''
ssh-keyscan -H github.com >> /home/${USER}/.ssh/known_hosts 2> /dev/null
ssh-keyscan -H bitbucket.org >> /home/${USER}/.ssh/known_hosts 2> /dev/null

# Setup directory permissions
chown -R ${USER}:${USER} /home/${USER}
chmod -R 755 /home/${USER}
chmod 700 /home/${USER}/.ssh/id_rsa

if false; then
  # Set password for ${USER}
  PASSWORD=$(mkpasswd ${SUDO_PASSWORD})
  usermod --password ${PASSWORD} ${USER}
else
  # Allow FPM restart without password prompt.
  echo "${USER} ALL=NOPASSWD: /usr/sbin/service php7.0-fpm reload" > /etc/sudoers.d/php-fpm
  echo "${USER} ALL=NOPASSWD: /usr/sbin/service php5-fpm reload" >> /etc/sudoers.d/php-fpm
fi

# => Configure Swap
# ----------------------------------------------------------------
if [ -f /swapfile ]; then
  echo "Swap exists."
else
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  echo "vm.swappiness=30" >> /etc/sysctl.conf
  echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
fi

# => Unattended updates and periodic cleaning
# ----------------------------------------------------------------
cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "Ubuntu xenial-security";
};
Unattended-Upgrade::Package-Blacklist {
    //
};
EOF

cat > /etc/apt/apt.conf.d/10periodic << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

##################################################################
##                                                              ##
##                      PHP & Composer                          ##
##                                                              ##
##################################################################

# => Install base PHP packages
# ----------------------------------------------------------------
apt-get install -y --allow-unauthenticated php7.1-cli php7.1-dev \
php-curl \
php-imap php-mysql php-memcached php-mcrypt php-mbstring \
php-xml php-imagick php7.1-zip php7.1-bcmath php-soap \
php7.1-intl php7.1-readline

apt-get install -y --allow-unauthenticated php7.1-fpm

# => Install composer
# ----------------------------------------------------------------
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# => Configure PHP CLI
# ----------------------------------------------------------------
sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.1/cli/php.ini
sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.1/cli/php.ini
sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.1/cli/php.ini
sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.1/cli/php.ini


# => Configure PHP FPM
# ----------------------------------------------------------------
sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.1/fpm/php.ini
sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.1/fpm/php.ini
sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.1/fpm/php.ini
sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.1/fpm/php.ini
sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.1/fpm/php.ini

# => Configure PHP sessions
# ----------------------------------------------------------------
chmod 733 /var/lib/php/sessions
chmod +t /var/lib/php/sessions
sed -i "s/\;session.save_path = .*/session.save_path = \"\/var\/lib\/php5\/sessions\"/" /etc/php/7.1/fpm/php.ini
sed -i "s/php5\/sessions/php\/sessions/" /etc/php/7.1/fpm/php.ini

# => Configure PHP to run as ${USER}
# ----------------------------------------------------------------
sed -i "s/^user = www-data/user = ${USER}/" /etc/php/7.1/fpm/pool.d/www.conf
sed -i "s/^group = www-data/group = ${USER}/" /etc/php/7.1/fpm/pool.d/www.conf
sed -i "s/;listen\.owner.*/listen.owner = ${USER}/" /etc/php/7.1/fpm/pool.d/www.conf
sed -i "s/;listen\.group.*/listen.group = ${USER}/" /etc/php/7.1/fpm/pool.d/www.conf
sed -i "s/;listen\.mode.*/listen.mode = 0666/" /etc/php/7.1/fpm/pool.d/www.conf
sed -i "s/;request_terminate_timeout.*/request_terminate_timeout = 60/" /etc/php/7.1/fpm/pool.d/www.conf

# => Restart service
# ----------------------------------------------------------------
service php7.1-fpm restart

##################################################################
##                                                              ##
##                           Redis                              ##
##                                                              ##
##################################################################

# => Install redis
# ----------------------------------------------------------------
apt-get install -y --allow-unauthenticated redis-server

# => Configure
# ----------------------------------------------------------------
sed -i 's/bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf
service redis-server restart

##################################################################
##                                                              ##
##                           Nginx                              ##
##                                                              ##
##################################################################
# => Install Nginx
# ----------------------------------------------------------------
apt-get install -y --allow-unauthenticated nginx

# => Configure Nginx
# ----------------------------------------------------------------

# Generate dhparam file.
echo "Generating dhpraam file this will take some time...";
openssl dhparam -out /etc/nginx/dhparams.pem 2048 &> /dev/null

# Disable default site.
rm /etc/nginx/sites-enabled/default
rm /etc/nginx/sites-available/default
service nginx restart

# Run nginx as ${USER}
sed -i "s/user www-data;/user ${USER};/" /etc/nginx/nginx.conf

# Some nginx configurations
sed -i "s/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/" /etc/nginx/nginx.conf
sed -i "s/worker_processes.*/worker_processes auto;/" /etc/nginx/nginx.conf
sed -i "s/# multi_accept.*/multi_accept on;/" /etc/nginx/nginx.conf

# => Install a catch-all server
# ----------------------------------------------------------------
cat > /etc/nginx/sites-available/catch-all << EOF
server {
    return 404;
}
EOF
ln -s /etc/nginx/sites-available/catch-all /etc/nginx/sites-enabled/catch-all

# => Restart service
# ----------------------------------------------------------------
service nginx restart
service nginx reload

# => Add ${USER} to www-data group
# ----------------------------------------------------------------
usermod -a -G www-data ${USER}
id ${USER}
groups ${USER}

block="server {
    listen 80;
    # listen 80 ssl http2;
    server_name .${PROJECT};
    root \"${HOME}/${PROJECT}/current/public\";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/${PROJECT}-error.log error;

    sendfile off;

    client_max_body_size 100m;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php7.0-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }

    # ssl_certificate     /etc/nginx/ssl/${PROJECT}.crt;
    # ssl_certificate_key /etc/nginx/ssl/${PROJECT}.key;
}
"

cat > "/tmp/${PROJECT}" << EOF
${block}
EOF
sudo mv /tmp/${PROJECT} /etc/nginx/sites-available/${PROJECT}
sudo ln -fs "/etc/nginx/sites-available/${PROJECT}" "/etc/nginx/sites-enabled/${PROJECT}"
mkdir -p ${HOME}/${PROJECT}
echo ${PROJECT} created

# => Install supervisor
# ----------------------------------------------------------------
apt-get install -y --allow-unauthenticated supervisor

# => Configure and start
# ----------------------------------------------------------------
systemctl enable supervisor.service
sudo cp /etc/supervisor/supervisord.conf /etc/supervisord.conf
service supervisor start
