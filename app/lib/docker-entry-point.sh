#!/bin/sh
# https://stackoverflow.com/a/38732187/1935918
set -e

if [ -f /app/tmp/pids/server.pid ]; then
  rm /app/tmp/pids/server.pid
fi

echo Migrating or creating database
bundle exec rake db:migrate || bundle exec rake db:setup
echo Database migration/creation done

# bundle exec rake after_party:run || true

#----- setup cron jobs
echo Setting up inspect job
bundle exec rake jobs:schedule
echo Done

echo Launching server
exec bundle exec "$@"
