#!/usr/bin/env bash

set -ex

apt-get update

# Determine external IP address
set +x
IP=`ifconfig eth1 | grep inet | awk '{print $2}' | sed 's/addr://'`
echo "IP address is $IP"
set -x

# Setup Apache
apt-get install -y apache2
a2enmod rewrite
apache_config="/etc/apache2/sites-available/magento2.conf"
cp /vagrant/magento2.vhost.conf ${apache_config}
sed -i "s/<host>/$IP/g" ${apache_config}
# Enable Magento virtual host
a2ensite magento2.conf
# Disable default virtual host
sudo a2dissite 000-default
# Create Magento root dir
magento_dir="/var/www/magento2"
mkdir ${magento_dir}

# Setup PHP
apt-get install -y php5 php5-mhash php5-mcrypt php5-curl php5-cli php5-mysql php5-gd php5-intl curl
ln -s /etc/php5/mods-available/mcrypt.ini /etc/php5/apache2/conf.d/20-mcrypt.ini
ln -s /etc/php5/mods-available/mcrypt.ini /etc/php5/cli/conf.d/20-mcrypt.ini
echo "date.timezone = America/Chicago" >> /etc/php5/cli/php.ini

# Restart Apache
service apache2 restart

# Setup MySQL
debconf-set-selections <<< 'mysql-server mysql-server/root_password password password'
debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password password'
apt-get install -q -y mysql-server-5.6 mysql-client-5.6
mysql -u root -ppassword -e "create database magento;"
mysql -u root -ppassword -e "GRANT ALL ON magento.* TO magento@localhost IDENTIFIED BY 'magento';"

# Setup Composer
cd /tmp
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
github_token="/vagrant/local.config/github.oauth.token"
if [ -f ${github_token} ]; then
    set +x
    echo "Installing GitHub OAuth token from ${github_token}..."
    composer config -g github-oauth.github.com `cat ${github_token}`
    set -x
fi

# Install Magento code base
cd ${magento_dir}
composer create-project --stability=beta magento/product-community-edition .

# Install Magento application
php -f setup/index.php install \
        --db_host=localhost \
        --db_name=magento \
        --db_user=magento \
        --db_pass=magento \
        --backend_frontname=admin \
        --base_url=http://${IP}/ \
        --language=en_US \
        --timezone=America/Chicago \
        --currency=USD \
        --admin_lastname=Admin \
        --admin_firstname=Admin \
        --admin_email=admin@example.com \
        --admin_username=admin \
        --admin_password=iamtheadmin \
        --use_secure=0

chown -R www-data:www-data .

# Deploy static view files for better performance
php -f dev/tools/Magento/Tools/View/deploy.php -- --verbose=0

set +x
echo "Installed Magento application in ${magento_dir}"
echo "Access front-end at http://$IP/"
echo "Access back-end at http://$IP/admin/"
