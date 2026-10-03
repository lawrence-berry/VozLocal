# Ruby for the build scripts and specs, so nothing runs on (or changes) the system Ruby.
# Use it through bin/dev, which builds this image and mounts the repo at /app.
FROM ruby:3.4-slim
WORKDIR /app/chrome
COPY Gemfile Gemfile.lock ./
RUN bundle install
