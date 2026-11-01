FROM public.ecr.aws/docker/library/php:8.3.36-fpm-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ffmpeg \
        git \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libonig-dev \
        libpng-dev \
        libxml2-dev \
        libzip-dev \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
        bcmath \
        ftp \
        gd \
        intl \
        mbstring \
        pcntl \
        pdo_mysql \
        sockets \
        xml \
        zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=public.ecr.aws/docker/library/composer:2 /usr/bin/composer /usr/local/bin/composer
COPY php-development.ini /usr/local/etc/php/conf.d/zz-development.ini
COPY php-fpm-development.conf /usr/local/etc/php-fpm.d/zz-development.conf

WORKDIR /app

EXPOSE 9000

CMD ["php-fpm", "-F"]
