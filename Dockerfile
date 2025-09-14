ARG RUBY_VERSION=${RUBY_VERSION:-3.4}
FROM ruby:${RUBY_VERSION}

RUN apt-get update && apt-get install -y \
    firefox-esr \
    xvfb \
    redis \
    && rm -rf /var/lib/apt/lists/*

# Set display for headless mode
ENV DISPLAY=:99

