# Shared CI image for every repo calling this repo's terraform-checks.yml/
# terraform-apply.yml reusable workflows: Terraform plus the handful of
# extra tools those workflows need, pinned so a routine CI run never picks
# up a surprise toolchain change underneath it. Built and pushed once per
# workflow run, from whichever repo calls it -- see terraform-checks.yml's
# build-image job.
FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

ARG TERRAFORM_VERSION=1.15.8
ARG TERRAFORM_SHA256=d25ce7b6902013ad905db3d2eab0be4cd905887fe88b81a6171b8d5503c31f3d

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        awscli \
        ca-certificates \
        curl \
        git \
        python3 \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/terraform.zip \
        "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && echo "${TERRAFORM_SHA256}  /tmp/terraform.zip" | sha256sum -c - \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && terraform -version
