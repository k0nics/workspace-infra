FROM public.ecr.aws/docker/library/php:8.3.36-fpm

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    unzip \
    curl \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libxml2-dev \
    libzip-dev \
    libonig-dev \
    ffmpeg \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j2docker compose -f projects/tisph-cms.yml up -d --force-recreate \
        pdo_mysql \
        gd \
        mbstring \
        xml \
        bcmath \
        zip \
        pcntl \
        ftp \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

WORKDIR /app

CMD ["php-fpm"]
