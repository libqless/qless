ARG RUBY_VERSION=${RUBY_VERSION:-3.4}
FROM ruby:${RUBY_VERSION}

RUN apt-get update && apt-get install -y \
    firefox-esr \
    xvfb \
    redis \
    vim \
    curl \
    git \
    tmux \
    && rm -rf /var/lib/apt/lists/*

RUN cat <<EOF >> ~/.inputrc
\$include /etc/inputrc
set editing-mode vi
set show-mode-in-prompt on
set vi-ins-mode-string ""
set vi-cmd-mode-string "[N]"
set keymap vi-insert
"\C-L": clear-screen
"\eb": backward-word
"\ef": forward-word
EOF

# better vim in dev container
RUN curl -fLo ~/.vimrc https://raw.githubusercontent.com/bak1an/dotvim/refs/heads/master/.vimrc
RUN vim -es -u ~/.vimrc -i NONE -c "PlugInstall" -c "qa" || exit 0
ENV TERM=xterm-256color
RUN echo 'set -g default-terminal "xterm-256color"' >> ~/.tmux.conf

# Set display for headless mode
ENV DISPLAY=:99
ENV EDITOR=vim

