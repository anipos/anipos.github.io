ARG VARIANT
FROM mcr.microsoft.com/devcontainers/ruby:${VARIANT}

ARG NODE_VERSION
RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && nvm install ${NODE_VERSION}"

CMD ["bundle", "exect", "jekyll", "server"]
