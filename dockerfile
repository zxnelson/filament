# Etapa de construcción
FROM php:8.2-apache AS builder

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    libicu-dev \
    zip \
    unzip \
    nodejs \
    npm

# Instalar extensiones de PHP (agregando intl y opcache)
RUN docker-php-ext-configure intl \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip intl opcache

# Instalar Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Establecer directorio de trabajo
WORKDIR /var/www/html

# Copiar archivos del proyecto
COPY . .

# Instalar dependencias de PHP (actualizar y generar lock)
RUN composer update --optimize-autoloader --no-dev && \
    composer dump-autoload --optimize

# Instalar dependencias de Node.js y compilar assets
RUN npm install && npm run build

# Etapa final
FROM php:8.2-apache

# Instalar dependencias necesarias para producción
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    libicu-dev \
    && docker-php-ext-configure intl \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip intl opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configuración de OPcache para producción
RUN echo 'opcache.enable=1\n\
opcache.memory_consumption=256\n\
opcache.interned_strings_buffer=16\n\
opcache.max_accelerated_files=20000\n\
opcache.validate_timestamps=0\n\
opcache.save_comments=1\n\
opcache.fast_shutdown=1' > /usr/local/etc/php/conf.d/opcache.ini

# Configuración adicional de PHP para rendimiento
RUN echo 'memory_limit=512M\n\
max_execution_time=300\n\
upload_max_filesize=50M\n\
post_max_size=50M\n\
realpath_cache_size=4096K\n\
realpath_cache_ttl=600' > /usr/local/etc/php/conf.d/performance.ini

# Habilitar módulos de Apache para rendimiento
RUN a2enmod rewrite expires headers deflate

# Configurar DocumentRoot de Apache para Laravel
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Configurar permisos de directorio y optimizaciones de Apache
RUN echo '<Directory /var/www/html/public>\n\
    Options -Indexes +FollowSymLinks\n\
    AllowOverride All\n\
    Require all granted\n\
    # Habilitar compresión\n\
    <IfModule mod_deflate.c>\n\
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript application/json\n\
    </IfModule>\n\
    # Caché del navegador\n\
    <IfModule mod_expires.c>\n\
        ExpiresActive On\n\
        ExpiresByType image/jpg "access plus 1 year"\n\
        ExpiresByType image/jpeg "access plus 1 year"\n\
        ExpiresByType image/gif "access plus 1 year"\n\
        ExpiresByType image/png "access plus 1 year"\n\
        ExpiresByType image/svg+xml "access plus 1 year"\n\
        ExpiresByType text/css "access plus 1 month"\n\
        ExpiresByType application/javascript "access plus 1 month"\n\
        ExpiresByType application/pdf "access plus 1 month"\n\
        ExpiresByType text/javascript "access plus 1 month"\n\
    </IfModule>\n\
</Directory>' > /etc/apache2/conf-available/laravel.conf \
    && a2enconf laravel

# Configuración de Apache para mejor rendimiento
RUN echo 'ServerTokens Prod\n\
ServerSignature Off\n\
KeepAlive On\n\
MaxKeepAliveRequests 100\n\
KeepAliveTimeout 5' >> /etc/apache2/apache2.conf

# Establecer directorio de trabajo
WORKDIR /var/www/html

# Copiar archivos desde el builder
COPY --from=builder /var/www/html /var/www/html

# Configurar permisos
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html/storage \
    && chmod -R 755 /var/www/html/bootstrap/cache

# Exponer puerto
EXPOSE 80

# Script de inicio optimizado
RUN echo '#!/bin/bash\n\
php artisan config:cache\n\
php artisan route:cache\n\
php artisan view:cache\n\
php artisan event:cache\n\
php artisan migrate --force\n\
php artisan optimize\n\
apache2-foreground' > /usr/local/bin/start.sh \
    && chmod +x /usr/local/bin/start.sh

CMD ["/usr/local/bin/start.sh"]
