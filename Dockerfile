FROM ruby:2.7.1-alpine AS base

#------------ intermediate container with specific dev tools
FROM base AS builder
# RUN ping -c 2 dl-cdn.alpinelinux.org
# RUN wget  --debug --verbose  http://dl-cdn.alpinelinux.org/alpine/v3.8/main/x86_64/APKINDEX.tar.gz
RUN apk add --update --virtual build-dependencies \
        build-base \
        gcc \
        git \
        libcurl \
        curl-dev \
        postgresql-dev \
        yarn \
        python3
ENV INSTALL_PATH /app
RUN mkdir -p ${INSTALL_PATH}
COPY Gemfile Gemfile.lock package.json yarn.lock  ${INSTALL_PATH}/
WORKDIR ${INSTALL_PATH}

# sassc https://github.com/sass/sassc-ruby/issues/146#issuecomment-608489863
RUN bundle config specific_platform x86_64-linux \
  && bundle config --local build.sassc --disable-march-tune-native

RUN bundle config --global frozen 1 &&\
    bundle install --deployment --without development test&&\
    yarn install --production

#----------- final tps
FROM base
ENV APP_PATH /imd
#----- minimum set of packages including PostgreSQL client, yarn
RUN apk add --no-cache --update tzdata libcurl postgresql-libs yarn

WORKDIR ${APP_PATH}
RUN adduser -Dh ${APP_PATH} userapp

#----- copy from previous container the dependency gems plus the current application files
USER userapp

COPY --chown=userapp:userapp --from=builder /app ${APP_PATH}/
RUN bundle install --deployment --without development test && \
    rm -fr .git && \
    yarn install --production

ENV \
    API_CPS_CLIENT_ID=""\
    API_CPS_CLIENT_SECRET=""\
    API_CPS_PASSWORD=""\
    API_CPS_USERNAME=""\
    CAPYBARA_DRIVER="wsl"\
    DB_DATABASE="rosso_development"\
    DB_HOST="db"\
    DB_PASSWORD="rosso"\
    DB_POOL=""\
    DB_USERNAME="rosso"\
    GRAPHQL_BEARER=""\
    GRAPHQL_HOST=https://www.mes-demarches.gov.pf\
    PORT=3000\
    RAILS_SERVE_STATIC_FILES="true"\
    SECRET_KEY_BASE="bcab70b0157b199a918f0a7f1177e5995d085a919dfb0cc6b2a92dc30877f99dbad5144fe5f64e2a22da70161e6c9a39ede54b54a21a4fc4b78fdf3de55088b1"


COPY --chown=userapp:userapp . ${APP_PATH}
RUN RAILS_ENV=production bundle exec rails assets:precompile

RUN chmod a+x $APP_PATH/app/lib/docker-entry-point.sh

EXPOSE 3000
ENTRYPOINT ["/imd/app/lib/docker-entry-point.sh"]
CMD ["rails", "server", "-b", "0.0.0.0"]





# git clone https://github.com/sipf/tps.git
# cd tps/
# Modify config/environments/production.rb with this parameters :
# config.force_ssl = false
# protocol: :http # everywhere
# config.active_storage.service = :local

# Add Dockerfile in this repository and build
# docker build -t sipf/tps:0.1.0 .

# docker run -p 5432:5432 -e POSTGRES_USER=tps -e POSTGRES_PASSWORD=tps -d postgres:9.6-alpine
# docker run --rm -e DB_HOST="192.168.1.45" sipf/tps:0.1.0 rails db:setup

# docker run -e DB_HOST="192.168.1.45" -e MAILTRAP_ENABLED="enabled" -e MAILTRAP_USERNAME="xxxxxxxx" -e MAILTRAP_PASSWORD="yyyyyyyy" -e APP_HOST="beta.mes-demarches.gov.pf" -d sipf/tps:0.1.0 rails jobs:work
# docker run -e DB_HOST="192.168.1.45" -e MAILTRAP_ENABLED="enabled" -e MAILTRAP_USERNAME="xxxxxxxx" -e MAILTRAP_PASSWORD="yyyyyyyy" -e APP_HOST="beta.mes-demarches.gov.pf" -d -p 80:3000 sipf/tps:0.1.0

# Modify your /etc/hosts file so beta.demarches-simplifiees.gov.pf match your host.
# Log to http://beta.demarches-simplifiees.gov.pf with your browser, it must works.
# login : test@exemple.fr
# password : "this is a very complicated password !"

# Add aditionnal administrator
# docker run --rm -e DB_HOST="192.168.1.45" sipf/tps:0.1.0 rake admin:list
# docker run --rm -e DB_HOST="192.168.1.45" sipf/tps:0.1.0 "rake admin:create_admin[leonard.tavae@informatique.gov.pf]"
# docker run --rm -e DB_HOST="192.168.1.45" sipf/tps:0.1.0 "rake admin:delete_admin[leonard.tavae@informatique.gov.pf]"

