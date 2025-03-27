FROM node:18.3.0-alpine as FrontendStage

COPY . /var/www/html
WORKDIR /var/www/html/

# Essentials
RUN apk add --no-cache tzdata
ENV TZ=Asia/Jakarta

RUN npm install
RUN npm run production
RUN npm run tailwind-production
RUN rm -rf /var/www/html/node_modules

FROM alpine:latest as BuildStage

WORKDIR /var/www/html/
COPY --from=FrontendStage /var/www/html /var/www/html/

RUN apk add --no-cache zip unzip curl nginx supervisor

# Installing bash
RUN apk add bash
RUN sed -i 's/bin\/ash/bin\/bash/g' /etc/passwd

# Installing PHP
RUN apk add --no-cache php82 \
    php82-common \
    php82-fpm \
    php82-pdo \
    php82-opcache \
    php82-zip \
    php82-gd \
    php82-phar \
    php82-iconv \
    php82-cli \
    php82-curl \
    php82-openssl \
    php82-mbstring \
    php82-exif \
    php82-tokenizer \
    php82-fileinfo \
    php82-json \
    php82-xml \
    php82-xmlreader \
    php82-xmlwriter \
    php82-simplexml \
    php82-dom \
    php82-pdo_mysql \
    php82-tokenizer \
    php82-pecl-redis

RUN ln -s /usr/bin/php82 /usr/bin/php

# Installing composer
RUN curl -sS https://getcomposer.org/installer -o composer-setup.php
RUN php composer-setup.php --install-dir=/usr/local/bin --filename=composer
RUN rm -rf composer-setup.php

# Configure supervisor
RUN mkdir -p /etc/supervisor.d/
COPY ./docker/supervisor/supervisord.ini /etc/supervisor.d/supervisord.ini

# Configure PHP
RUN mkdir -p /run/php/
RUN touch /run/php/php8.2-fpm.pid

COPY ./docker/php/php-fpm.conf /etc/php82/php-fpm.conf
COPY ./docker/php/php.ini-production /etc/php82/php.ini

# Configure nginx
COPY ./docker/nginx/nginx.conf /etc/nginx/
COPY ./docker/nginx/webserver.conf /etc/nginx/http.d/default.conf

RUN mkdir -p /run/nginx/
RUN touch /run/nginx/nginx.pid

RUN ln -sf /dev/stdout /var/log/nginx/access.log
RUN ln -sf /dev/stderr /var/log/nginx/error.log

# Building process
COPY . .
RUN composer install
RUN chown -R nobody:nobody /var/www/html/storage

# Run a cron job
ADD ./docker/cron/crontab.txt /crontab.txt
RUN /usr/bin/crontab /crontab.txt

# add log for supervisor laravel worker
RUN touch /var/www/html/storage/logs/worker.log

# Generate Laravel app encryption key
RUN cp .env.example .env
RUN php artisan key:generate --ansi
RUN php artisan vendor:publish --all
RUN php artisan storage:link

RUN chown -R nginx:nginx /var/www/html -v
RUN chmod -R 777 /var/www/html -v
RUN chown -R nginx:nginx /var/lib/nginx -v
RUN chmod -R 755 /var/lib/nginx -v
RUN chmod -R 755 /var/log/nginx -v

# Exposing port 80 (http)
EXPOSE 80

# Auto start supervisor on start
CMD ["/usr/bin/supervisord"]