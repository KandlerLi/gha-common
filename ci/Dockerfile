# Shared CI image, built by build-ci-image.yml when this directory changes and weekly: see README.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

ARG TERRAFORM_VERSION=1.15.8
ARG TERRAFORM_SHA256=d25ce7b6902013ad905db3d2eab0be4cd905887fe88b81a6171b8d5503c31f3d

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        awscli \
        ca-certificates \
        curl \
        git \
        jq \
        python3 \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/terraform.zip \
        "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && echo "${TERRAFORM_SHA256}  /tmp/terraform.zip" | sha256sum -c - \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && terraform -version
