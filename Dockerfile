FROM php:7.4-apache

ENV MDL_DB_TYPE=""
ENV MDL_DB_HOST=""
ENV MDL_DB_NAME=""
ENV MDL_DB_USER=""
ENV MDL_DB_PASS=""
ENV MDL_WEB_ROOT=""
ENV MDL_DATA=""

ENV PHP_EXTENSIONS="gd intl ldap opcache pdo_mysql soap xmlrpc zip exif"
ENV PHP_TIMEZONE=UTC

# Install required packages
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        git \
        jq \
        libfreetype6-dev \
        libjpeg-dev \
        libicu-dev \
        libldap2-dev \
        libpng-dev \
        libxml2-dev \
        libzip-dev \
        cron \
        ghostscript \
        unoconv \
        poppler-utils \
        dos2unix \
        sudo \
        awscli \
        curl \
        redis-tools \
 && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j$(nproc) $PHP_EXTENSIONS \
 && docker-php-ext-install mysqli

# Install PHP Redis
RUN apt-get install -y autoconf wget build-essential && \
    wget https://pecl.php.net/get/redis-5.3.7.tgz && \
    tar xzf redis-5.3.7.tgz && \
    cd redis-5.3.7 && \
    phpize && \
    ./configure && \
    make && \
    make install && \
    echo "extension=redis.so" >> /usr/local/etc/php/php.ini-development && \
    echo "extension=redis.so" >> /usr/local/etc/php/php.ini-production && \
    apt-get purge --autoremove -y autoconf wget build-essential && \
    cd .. && \
    rm redis-5.3.7.tgz && \
    rm -rf redis-5.3.7
 
# Enable mod_headers
RUN a2enmod headers

# Set permissions for moodledata 
RUN mkdir -p /var/www/html/moodledata \
 && chown -R www-data:www-data /var/www/html/moodledata \
 && chmod -R 777 /var/www/html/moodledata 

# Set the working directory to /app
WORKDIR /var/www/html

# Copy the entry point script into the Docker image
COPY entrypoint_script.sh /var/www/html/

# Remove any carriage return characters in the entrypoint.sh file
RUN sed -i 's/\r//' /var/www/html/entrypoint_script.sh

# Make the script executable
RUN chmod +x /var/www/html/entrypoint_script.sh

# Set the entry point to the script
#ENTRYPOINT ["/var/www/html/entrypoint_script.sh"]
