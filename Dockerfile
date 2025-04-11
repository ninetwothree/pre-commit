FROM docker.io/library/golang:latest AS build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /go/src/github.com/zricethezav/
RUN git clone https://github.com/gitleaks/gitleaks.git
WORKDIR /go/src/github.com/zricethezav/gitleaks
RUN VERSION=$(git describe --tags --abbrev=0) && \
  CGO_ENABLED=0 go build -o bin/gitleaks -ldflags "-X=github.com/zricethezav/gitleaks/v8/cmd.Version=${VERSION}"

FROM ghcr.io/antonbabenko/pre-commit-terraform:latest
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Install prerequisites
RUN apk add --no-cache curl make npm cabal

# Install trufflehog
RUN curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b /usr/local/bin

# Install gitleaks
COPY --from=build /go/src/github.com/zricethezav/gitleaks/bin/* /usr/bin/
RUN git clone https://github.com/gitleaks/gitleaks.github
WORKDIR /tmp/gitleaks
RUN curl -sLO "https://go.dev/dl/go$(grep '^go ' go.mod | awk '{print $2}').linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" && \
  tar -C /usr/local -xzf "go$(grep '^go ' go.mod | awk '{print $2}').linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" && \
  PATH=$PATH:/usr/local/go/bin make build

# Install shellcheck
RUN curl -sLO "https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.$(uname -m).tar.xz" && \
  tar -xJv "shellcheck-stable.linux.$(uname -m).tar.xz" && \
  cp "shellcheck-stable/shellcheck" /usr/local/bin/

RUN npm install -g dockerfilelint
# Install hadolint
RUN curl -s "https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-$(uname -m | sed 's/aarch64/arm64/')" -o /usr/local/bin/hadolint \
  && chmod +x /usr/local/bin/hadolint

# Install pre-commit-hooks
RUN git init /tmp/repo
COPY .pre-commit-config.yaml /tmp/repo/
WORKDIR /tmp/repo
RUN pre-commit install-hooks
WORKDIR /lint
RUN rm -rf /tmp/repo

ENTRYPOINT ["pre-commit"]
