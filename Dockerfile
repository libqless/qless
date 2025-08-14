FROM ruby:3.3.1

RUN apt-get update && apt-get install -y \
    firefox-esr \
    xvfb \
    redis \
    && rm -rf /var/lib/apt/lists/*

# Set display for headless mode
ENV DISPLAY=:99

