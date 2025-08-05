FROM docker.io/library/golang:latest AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /go/src/github.com/zricethezav/
RUN git clone https://github.com/gitleaks/gitleaks.git
WORKDIR /go/src/github.com/zricethezav/gitleaks
RUN bash -o pipefail -c '\
  VERSION=$(git describe --tags --abbrev=0) && \
  CGO_ENABLED=0 go build -o bin/gitleaks -ldflags "-X=github.com/zricethezav/gitleaks/v8/cmd.Version=${VERSION}"'

FROM node:20-alpine AS nodejs
WORKDIR /app
RUN npm install -g \
    corepack \
    eslint \
    jest \
    knex \
    license-checker \
    license-checker-rseidelsohn \
    npm \
    prettier \
    stylelint \
    ts-node \
    typedoc \
    typescript \
    vite

  FROM ghcr.io/antonbabenko/pre-commit-terraform:latest
  SHELL ["/bin/bash", "-o", "pipefail", "-c"]
  RUN apk add --no-cache curl make g++
  COPY --from=nodejs /usr/local/lib/node_modules /usr/local/lib/node_modules
  COPY --from=nodejs /usr/local/bin /tmp/nodejs-bin
  COPY --from=nodejs /lib/ /tmp/nodejs-lib
  # Merge with existing content
  RUN cp -a /tmp/nodejs-bin/. /usr/local/bin/ && \
      cp -a /tmp/nodejs-lib/. /lib/ && \
      rm -rf /tmp/nodejs-bin /tmp/nodejs-lib /tmp/nodejs-lib64

# Install trufflehog
RUN curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin

# Install gitleaks
COPY --from=build /go/src/github.com/zricethezav/gitleaks/bin/* /usr/bin/
WORKDIR /tmp
RUN git clone https://github.com/gitleaks/gitleaks.git
WORKDIR /tmp/gitleaks
RUN curl -sLO "https://go.dev/dl/go$(grep '^go ' go.mod | awk '{print $2}').linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" && \
  tar -C /usr/local -xzf "go$(grep '^go ' go.mod | awk '{print $2}').linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" && \
  PATH=$PATH:/usr/local/go/bin make build

# Install shellcheck
RUN curl -sLO "https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.$(uname -m).tar.xz" && \
  tar -xJf "shellcheck-stable.linux.$(uname -m).tar.xz" && \
  cp "shellcheck-stable/shellcheck" /usr/local/bin/ && \
  rm -rf "shellcheck-stable" "shellcheck-stable.linux.$(uname -m).tar.xz"

# Install hadolint
RUN LATEST_RELEASE=$(curl -s https://api.github.com/repos/hadolint/hadolint/releases/latest | jq -r '.tag_name') && \
  curl -sL "https://github.com/hadolint/hadolint/releases/download/${LATEST_RELEASE}/hadolint-Linux-$(uname -m | sed 's/aarch64/arm64/')" -o /usr/local/bin/hadolint && \
  chmod +x /usr/local/bin/hadolint

# Install python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN python -m venv .venv && \
  .venv/bin/pip install --no-cache-dir -r requirements.txt && \
  rm requirements.txt

RUN git clone https://github.com/pre-commit/pre-commit-hooks /opt/pre-commit-hooks
WORKDIR /opt/pre-commit-hooks
RUN python setup.py install

# Install pre-commit-hooks
RUN git init /tmp/repo && \
    LATEST_TAG=$(curl -s https://api.github.com/repos/pre-commit/pre-commit-hooks/releases/latest | jq -r .tag_name) && \
    echo "Latest tag is $LATEST_TAG" && \
    echo "repos:" > /tmp/repo/.pre-commit-config.yaml && \
    echo "  - repo: https://github.com/pre-commit/pre-commit-hooks.git" >> /tmp/repo/.pre-commit-config.yaml && \
    echo "    rev: $LATEST_TAG" >> /tmp/repo/.pre-commit-config.yaml && \
    echo "    hooks:" >> /tmp/repo/.pre-commit-config.yaml && \
    grep 'id:' /opt/pre-commit-hooks/.pre-commit-hooks.yaml | awk '{print "      "$0}' >> /tmp/repo/.pre-commit-config.yaml

# tf scripts
WORKDIR /opt/
RUN git clone https://github.com/antonbabenko/pre-commit-terraform.git && \
    LATEST_TAG=$(curl -s https://api.github.com/repos/antonbabenko/pre-commit-terraform/releases/latest | jq -r .tag_name) && \
    echo "Latest tag is $LATEST_TAG" && \
    echo "  - repo: https://github.com/antonbabenko/pre-commit-terraform.git" >> /tmp/repo/.pre-commit-config.yaml && \
    echo "    rev: $LATEST_TAG" >> /tmp/repo/.pre-commit-config.yaml && \
    echo "    hooks:" >> /tmp/repo/.pre-commit-config.yaml && \
    grep 'id:' /opt/pre-commit-terraform/.pre-commit-hooks.yaml | awk '{print "      "$0}' >> /tmp/repo/.pre-commit-config.yaml

RUN pip install --no-cache-dir cfn-lint

WORKDIR /tmp/repo
RUN pre-commit install-hooks
WORKDIR /lint
RUN rm -rf /tmp/repo
ENV PATH="/usr/local/bin:/opt/pre-commit-hooks:/opt/pre-commit-terraform/hooks:${PATH}"
ENTRYPOINT ["pre-commit"]
