FROM debian:stretch-slim

RUN apt-get update -yy && apt-get install -yy curl unzip

ARG TF=0.15.1
ARG AWS=2.0.30

ADD https://releases.hashicorp.com/terraform/${TF}/terraform_${TF}_linux_amd64.zip terraform.zip
ADD https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS}.zip awscli.zip

RUN unzip terraform.zip \
  && rm terraform.zip \
  && mv ./terraform /usr/local/bin

RUN unzip awscli.zip \
  && ./aws/install \
  && rm -rf awscli.zip aws
