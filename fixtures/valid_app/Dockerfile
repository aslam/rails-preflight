# syntax = docker/dockerfile:experimental
FROM ruby:2.5.9-buster as base

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# Needs to be in /usr/src/app for sumologic container logging to work
WORKDIR /usr/src/app

COPY Gemfile Gemfile
COPY Gemfile.lock Gemfile.lock
COPY config/database.yml config/database.yml

FROM base AS prod-install

RUN gem install bundler -v '1.17.3'

RUN --mount=type=secret,id=GITHUB_USER --mount=type=secret,id=GITHUB_TOKEN \ 
		GITHUB_USER="$(cat /run/secrets/GITHUB_USER)" GITHUB_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)" && \
		bundle config rubygems.pkg.github.com "$GITHUB_USER:$GITHUB_TOKEN" ; \
		EXIT_STATUS=0 ; \
		bundle install --without development test -j4 --retry 3 || EXIT_STATUS=$? ; \
		bundle config unset rubygems.pkg.github.com ; \
		exit $EXIT_STATUS

FROM prod-install AS test-install

RUN --mount=type=secret,id=GITHUB_USER --mount=type=secret,id=GITHUB_TOKEN \ 
		GITHUB_USER="$(cat /run/secrets/GITHUB_USER)" GITHUB_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)" && \
		bundle config rubygems.pkg.github.com "$GITHUB_USER:$GITHUB_TOKEN" ; \
		EXIT_STATUS=0 ; \
		bundle install --with development test -j4 --retry 3 || EXIT_STATUS=$? ; \
		bundle config unset rubygems.pkg.github.com ; \
		exit $EXIT_STATUS

FROM base AS development

ARG ZSCALER_CERT
RUN if [ ! -z "$ZSCALER_CERT" ]; then \
		echo "$ZSCALER_CERT" > /usr/local/share/ca-certificates/zscaler-root-ca.crt && \
		update-ca-certificates; \
	fi

RUN gem install bundler -v '1.17.3'
	
RUN --mount=type=secret,id=GITHUB_TOKEN \
		GITHUB_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)" && \
		bundle config rubygems.pkg.github.com "$GITHUB_TOKEN:x-oauth-basic" ; \
		bundle install --with development test -j4 --retry 3 && \
		bundle config unset rubygems.pkg.github.com

FROM ruby:2.5.9-buster as post-install

RUN echo "deb http://archive.debian.org/debian buster main" > /etc/apt/sources.list && \
    echo "deb http://archive.debian.org/debian-security buster/updates main" >> /etc/apt/sources.list

ADD https://archive.debian.org/debian/pool/main/libj/libjpeg8/libjpeg8_8b-1_amd64.deb /root/libjpeg-turbo8_8b.deb
ADD http://archive.debian.org/debian/pool/main/libp/libpng/libpng12-0_1.2.50-2+deb8u3_amd64.deb /root/libpng12.deb

RUN apt-get update -qq; \
  apt-get install -y --no-install-recommends multiarch-support \
  default-libmysqlclient-dev imagemagick ftp nodejs; \
  ldconfig; \
  dpkg -i /root/*.deb; \
  addgroup --gid 1000 --system app && \
  adduser --uid 1000 --gid 1000 --system --home /usr/src/app app; \
  mkdir -p /usr/src/app/log && chown app:app /usr/src/app/log; \
  mkdir -p /etc/rails/keys && chown app:app /etc/rails/keys;

FROM post-install AS test

COPY --from=test-install /usr/local/bundle /usr/local/bundle
COPY  . /usr/src/app
WORKDIR /usr/src/app

FROM post-install AS prod

COPY --from=prod-install /usr/local/bundle /usr/local/bundle
COPY --chown=app:app . /usr/src/app

USER app
WORKDIR /usr/src/app

RUN RAILS_ENV=production bundle exec rake assets:precompile

ARG COMMIT_SHORT_HASH
RUN echo "COMMIT_HASH=$COMMIT_SHORT_HASH" > .env

EXPOSE 3000
CMD [ "bash", "./start.sh" ]
