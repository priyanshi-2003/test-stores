# OpenCart 4.1.0.4 on PHP 8.3 + Apache.
# OpenCart 4.1 needs PHP >= 8.1 with curl, gd, mbstring, zip, zlib (+ mysqli for MariaDB).
# The PHP image already has curl, mbstring and zlib; gd, mysqli and zip are added.
FROM docker.io/library/php:8.3.37-apache

ARG PHP_EXT_INSTALLER=2.13.4
RUN curl -fsSL -o /usr/local/bin/install-php-extensions \
      "https://github.com/mlocati/docker-php-extension-installer/releases/download/${PHP_EXT_INSTALLER}/install-php-extensions" \
 && chmod +x /usr/local/bin/install-php-extensions \
 && install-php-extensions gd mysqli zip \
 && a2enmod rewrite

ARG OC_VERSION=4.1.0.4
RUN curl -fsSL -o /tmp/oc.zip "https://github.com/opencart/opencart/releases/download/${OC_VERSION}/opencart-${OC_VERSION}.zip" \
 && cd /tmp && php -r '$z = new ZipArchive; $z->open("/tmp/oc.zip") === true or exit(1); $z->extractTo("/tmp/oc"); $z->close();' \
 && cp -a /tmp/oc/upload/. /var/www/html/ \
 && cp /var/www/html/config-dist.php /var/www/html/config.php \
 && cp /var/www/html/admin/config-dist.php /var/www/html/admin/config.php \
 && chown -R www-data:www-data /var/www/html \
 && rm -rf /tmp/oc /tmp/oc.zip
