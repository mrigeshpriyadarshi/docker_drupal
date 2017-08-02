# Use an official Ubuntu runtime as a base image
FROM ubuntu:16.04
MAINTAINER Mrigesh <mrigeshpriyadarshi@gmail.com>


RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8


ENV DEBIAN_FRONTEND noninteractive
ENV DRUPAL_VERSION 8.3.5

# Install packages.
RUN apt-get update
RUN apt-get install -y \
	vim \
	git \
	apache2 \
	php7.0-common \
	php7.0-cli \
	php7.0-dev \
	php7.0-fpm \
	libpcre3-dev \
	php7.0-gd \
	php7.0-curl \
	php7.0-imap \
	php7.0-json \
	php7.0-opcache \
	php7.0-xml \
	php7.0-mbstring \
	sqlite3 libsqlite3-dev \
	php-curl \
	php7.0-sqlite \
	php-apcu \
	php-mysql \
	libapache2-mod-php \
	curl \
	openssh-server \
	phpmyadmin \
	wget \
	unzip \
	cron \
	supervisor
RUN apt-get clean

# Setup PHP.
RUN sed -i 's/display_errors = Off/display_errors = On/' /etc/php/7.0/apache2/php.ini
RUN sed -i 's/display_errors = Off/display_errors = On/' /etc/php/7.0/cli/php.ini

# Setup Apache.
# In order to run our Simpletest tests, we need to make Apache
# listen on the same port as the one we forwarded. Because we use
# 8080 by default, we set it up for that port.
RUN sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
RUN sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www/' /etc/apache2/sites-available/000-default.conf
RUN sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www/' /etc/apache2/sites-available/default-ssl.conf
RUN echo "Listen 8080" >> /etc/apache2/ports.conf
RUN echo "Listen 8443" >> /etc/apache2/ports.conf
RUN echo "Listen 8888" >> /etc/apache2/ports.conf
RUN sed -i 's/VirtualHost \*:80/VirtualHost \*:8888/' /etc/apache2/sites-available/000-default.conf
RUN sed -i 's/VirtualHost __default__:443/VirtualHost _default_:443 _default_:8443/' /etc/apache2/sites-available/default-ssl.conf
RUN a2enmod rewrite
RUN a2enmod ssl
RUN a2ensite default-ssl.conf

# Setup SSH.
RUN echo 'root:root' | chpasswd
RUN sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN mkdir /var/run/sshd && chmod 0755 /var/run/sshd && mkdir -p /root/.ssh/ && touch /root/.ssh/authorized_keys
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Install Composer.
RUN curl -sS https://getcomposer.org/installer | php
RUN mv composer.phar /usr/local/bin/composer

# Install Drush 8.
RUN composer global require drush/drush:8.*
RUN composer global update
# Unfortunately, adding the composer vendor dir to the PATH doesn't seem to work. So:
RUN ln -s /root/.composer/vendor/bin/drush /usr/local/bin/drush

# Install Drupal Console. There are no stable releases yet, so set the minimum 
# stability to dev.
RUN curl https://drupalconsole.com/installer -L -o drupal.phar && \
	mv drupal.phar /usr/local/bin/drupal && \
	chmod +x /usr/local/bin/drupal
RUN drupal init

# Install Drupal.
RUN rm -rf /var/www
RUN cd /var && \
	drush dl drupal-$DRUPAL_VERSION && \
	mv /var/drupal* /var/www

RUN mkdir -p /var/www/sites/default/files && \
	chmod a+w /var/www/sites/default -R && \
	mkdir /var/www/sites/all/modules/contrib -p && \
	mkdir /var/www/sites/all/modules/custom && \
	mkdir /var/www/sites/all/themes/contrib -p && \
	mkdir /var/www/sites/all/themes/custom && \
	cp /var/www/sites/default/default.settings.php /var/www/sites/default/settings.php && \
	cp /var/www/sites/default/default.services.yml /var/www/sites/default/services.yml && \
	chmod 0664 /var/www/sites/default/settings.php && \
	chmod 0664 /var/www/sites/default/services.yml && \
	chown -R www-data:www-data /var/www/


# Setup Supervisor.
RUN echo '[program:apache2]\ncommand=/bin/bash -c "source /etc/apache2/envvars && exec /usr/sbin/apache2 -DFOREGROUND"\nautorestart=true\n\n' >> /etc/supervisor/supervisord.conf
RUN echo '[program:sshd]\ncommand=/usr/sbin/sshd -D\n\n' >> /etc/supervisor/supervisord.conf
RUN echo '[program:cron]\ncommand=cron -f\nautorestart=false \n\n' >> /etc/supervisor/supervisord.conf

# FROM mrigeshpriyadarshi/drupal_base:latest

RUN cd /var/www && \
	drush si -y standard --db-url=sqlite:///var/www/sites/all/files/.ht.sqlite --account-pass=admin && \
	chown -R www-data.www-data .

EXPOSE 3306 22 8888
CMD exec supervisord -n
