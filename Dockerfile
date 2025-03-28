ARG PHP_VERSION=8.3
ARG USER=www-data

# --- Builder Stage ---
# Builds Caddy with FrankenPHP and custom modules
FROM dunglas/frankenphp:latest-builder-php${PHP_VERSION} AS builder

# Copy xcaddy
COPY --from=caddy:builder /usr/bin/xcaddy /usr/bin/xcaddy

# Build FrankenPHP/Caddy binary with modules
ENV CGO_ENABLED=1 XCADDY_SETCAP=1 XCADDY_GO_BUILD_FLAGS='-ldflags="-w -s" -trimpath'
COPY ./sidekick/middleware/cache ./cache

RUN xcaddy build \
    --output /usr/local/bin/frankenphp \
    --with github.com/dunglas/frankenphp=./ \
    --with github.com/dunglas/frankenphp/caddy=./caddy/ \
    --with github.com/dunglas/caddy-cbrotli \
    # Add extra Caddy modules here if needed
    --with github.com/stephenmiracle/frankenwp/sidekick/middleware/cache=./cache

# --- Final Stage ---
# Based on FrankenPHP base image, without WordPress specifics
FROM dunglas/frankenphp:latest-php${PHP_VERSION} AS base

# Bring the globally defined USER argument into this stage's scope
ARG USER

LABEL org.opencontainers.image.title="Custom FrankenPHP Environment"
LABEL org.opencontainers.image.description="FrankenPHP/Caddy environment ready for externally mounted PHP applications (like WordPress)."
# Add other labels as needed

# Copy the custom-built FrankenPHP/Caddy binary
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

ENV PHP_INI_SCAN_DIR=$PHP_INI_DIR/conf.d

# Install necessary packages and PHP extensions (kept from original)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    ghostscript \
    curl \
    libonig-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libzip-dev \
    unzip \
    git \
    libjpeg-dev \
    libwebp-dev \
    libzip-dev \
    libmemcached-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN install-php-extensions \
    bcmath \
    exif \
    gd \
    intl \
    mysqli \
    zip \
    imagick/imagick@master \
    opcache

# Apply PHP configuration (kept from original)
RUN cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
COPY php.ini $PHP_INI_DIR/conf.d/wp.ini

# Set recommended PHP.ini settings (kept from original)
RUN set -eux; \
    { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    } > $PHP_INI_DIR/conf.d/opcache-recommended.ini
RUN { \
    echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
    echo 'display_errors = Off'; \
    echo 'display_startup_errors = Off'; \
    echo 'log_errors = On'; \
    echo 'error_log = /dev/stderr'; \
    echo 'log_errors_max_len = 1024'; \
    echo 'ignore_repeated_errors = On'; \
    echo 'ignore_repeated_source = Off'; \
    echo 'html_errors = Off'; \
    } > $PHP_INI_DIR/conf.d/error-logging.ini

# Install WP-CLI (kept from original)
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp

# Caddyfile will be mounted via docker-compose

# Create user, set capabilities, create web root, set permissions
RUN (id -u ${USER} &>/dev/null || useradd -ms /bin/bash ${USER}) && \
    setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp && \
    mkdir -p /var/www /data/caddy /config/caddy && \
    chown -R ${USER}:${USER} /var/www /data/caddy /config/caddy

# Set working directory
WORKDIR /var/www

# Switch to non-root user
USER ${USER}

# Expose default ports (optional but good practice)
EXPOSE 80 443 443/udp

# Default command to run Caddy with the specified config
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
