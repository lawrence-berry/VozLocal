# Ruby, Node, zsh (for the terminal's host), ffmpeg (for bin/build-gifs) and Playwright's Chromium for the build scripts and specs, so nothing runs on (or changes) the
# system Ruby. Use it through bin/dev, which builds this image and mounts the repo at /app.
FROM ruby:3.4-slim

# The Playwright driver (npm) must match the playwright-ruby-client gem's minor version.
ARG PLAYWRIGHT=1.63.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends nodejs npm zsh ffmpeg \
 && npm install -g playwright@$PLAYWRIGHT \
 && playwright install --with-deps --no-shell chromium \
 && rm -rf /var/lib/apt/lists/* /root/.npm

WORKDIR /app/chrome
COPY Gemfile Gemfile.lock ./
RUN bundle install
