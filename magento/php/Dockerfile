# PHP 8.3 + Apache with every PHP extension Magento 2.4.8 requires.
FROM docker.io/library/php:8.3.37-apache

# Magento 2.4.8 needs: bcmath ctype curl dom ftp gd hash iconv intl mbstring openssl pdo_mysql
# simplexml soap sodium xsl zip. The PHP image already has the rest; these are added
# (sockets and opcache are recommended). The installer also adds the system libraries they need.
ARG PHP_EXT_INSTALLER=2.13.4
RUN curl -fsSL -o /usr/local/bin/install-php-extensions \
      "https://github.com/mlocati/docker-php-extension-installer/releases/download/${PHP_EXT_INSTALLER}/install-php-extensions" \
 && chmod +x /usr/local/bin/install-php-extensions \
 && install-php-extensions bcmath ftp gd intl pdo_mysql soap sockets xsl zip opcache

# Composer 2.8 (Magento needs Composer 2; 2.8 avoids 2.9's default blocking of packages with advisories).
COPY --from=docker.io/library/composer:2.8.12 /usr/bin/composer /usr/local/bin/composer

# Apache serves Magento's pub/ folder; .htaccess rewrites are on (the PHP image sets AllowOverride All).
RUN a2enmod rewrite headers expires \
 && sed -ri 's!/var/www/html!/var/www/html/pub!g' /etc/apache2/sites-available/*.conf

RUN { \
      echo 'memory_limit = 4G'; \
      echo 'max_execution_time = 1800'; \
      echo 'realpath_cache_size = 10M'; \
      echo 'realpath_cache_ttl = 7200'; \
      echo 'opcache.memory_consumption = 512'; \
      echo 'opcache.max_accelerated_files = 60000'; \
    } > /usr/local/etc/php/conf.d/magento.ini
