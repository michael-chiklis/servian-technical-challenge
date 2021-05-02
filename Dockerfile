FROM debian:stretch-slim

RUN apt-get update -yy \
  && apt-get install -yy \
    awscli \
    curl \
    unzip

ARG VERSION=0.15.1

ADD https://releases.hashicorp.com/terraform/${VERSION}/terraform_${VERSION}_linux_amd64.zip \
  terraform.zip

RUN unzip terraform.zip \
  && rm terraform.zip \
  && mv ./terraform /usr/local/bin
