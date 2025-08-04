### ---------- STAGE 1: Builder ----------
FROM ruby:3.3.1-slim AS builder

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    gnupg \
    libpq-dev \
    ca-certificates \
    tzdata \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install newer Node.js (18.x LTS) and Yarn
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn

# Add app user
ENV APP_PATH=/app
RUN useradd -m -d $APP_PATH userapp

# Install bun as root and make it globally available
RUN curl -fsSL https://bun.sh/install | bash && \
    mv /root/.bun/bin/bun /usr/local/bin/bun && \
    chmod +x /usr/local/bin/bun

USER userapp
WORKDIR $APP_PATH

# Copy app files and install dependencies
COPY --chown=userapp:userapp Gemfile Gemfile.lock package.json bun.lock ./

# Install Ruby gems
RUN bundle config specific_platform x86_64-linux &&\
    bundle config deployment true &&\
    bundle config without "development test" &&\
    bundle install

# Install JS dependencies with bun
RUN bun install

# Copy rest of the application and precompile assets
COPY --chown=userapp:userapp . .

ENV APP_HOST="localhost"
# SECRET_KEY_BASE should be provided at runtime via environment variables

# Build assets with CSS compilation using legacy OpenSSL for Node.js 18 compatibility
# Use temporary SECRET_KEY_BASE for asset compilation only
RUN NODE_OPTIONS="--openssl-legacy-provider" \
    SECRET_KEY_BASE="temp-key-for-asset-compilation-only" \
    RAILS_ENV=production \
    bundle exec rails assets:precompile

### ---------- STAGE 2: Final image ----------
FROM ruby:3.3.1-slim

# Install runtime dependencies + LibreOffice + Fonts
ENV DEBIAN_FRONTEND=noninteractive
RUN echo "deb http://deb.debian.org/debian bullseye main contrib" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bullseye-security main contrib" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian bullseye-updates main contrib" >> /etc/apt/sources.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    curl \
    default-jre-headless \
    fontconfig \
    fonts-crosextra-carlito \
    fonts-crosextra-caladea \
    fonts-liberation \
    fonts-dejavu \
    fonts-freefont-ttf \
    gnupg \
    libpq5 \
    libreoffice \
    ttf-mscorefonts-installer \
    tzdata \
    unzip \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn \
    && curl -fsSL https://bun.sh/install | bash \
    && mv /root/.bun/bin/bun /usr/local/bin/bun \
    && chmod +x /usr/local/bin/bun \
    && fc-cache -fv \
    && rm -rf /var/lib/apt/lists/*

#----- user/install path setup
# Create app user
ENV APP_PATH=/app
RUN useradd -m -d $APP_PATH userapp
USER userapp
WORKDIR $APP_PATH

# Copy from builder
COPY --chown=userapp:userapp --from=builder /app /app
COPY --chown=userapp:userapp --from=builder /usr/local/bundle /usr/local/bundle

# Set env variables
ENV RAILS_SERVE_STATIC_FILES="true" \
    RAILS_RELATIVE_URL_ROOT="/"

# Entrypoint & launch
RUN chmod a+x $APP_PATH/app/lib/docker-entry-point.sh

EXPOSE 3000
ENTRYPOINT ["./app/lib/docker-entry-point.sh"]
CMD ["rails", "server", "-b", "0.0.0.0"]
