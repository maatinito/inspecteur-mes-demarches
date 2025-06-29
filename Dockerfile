### ---------- STAGE 1: Builder ----------
FROM ruby:3.1.2-slim AS builder

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    gnupg \
    libpq-dev \
    nodejs \
    ca-certificates \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Install bun
RUN curl -fsSL https://bun.sh/install | bash


# Add app user
ENV APP_PATH=/app
RUN useradd -m -d $APP_PATH userapp
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
ENV PATH="/app/.bun/bin:$PATH"
RUN bun install

# Copy rest of the application and precompile assets
COPY --chown=userapp:userapp . .

ENV APP_HOST="localhost"\
    SECRET_KEY_BASE="bcab70b0157b199a918f0a7f1177e5995d085a919dfb0cc6b2a92dc30877f99dbad5144fe5f64e2a22da70161e6c9a39ede54b54a21a4fc4b78fdf3de55088b2"

RUN RAILS_ENV=production bundle exec rails assets:precompile && \
    bun run build:css

### ---------- STAGE 2: Final image ----------
FROM ruby:3.1.2-slim

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
    libpq5 \
    libreoffice \
    nodejs \
    ttf-mscorefonts-installer \
    tzdata \
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
