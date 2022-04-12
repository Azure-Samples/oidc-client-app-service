#!make

DOCKER_BIN := docker
IMAGE_NAME := sample-oidc-client-app
DEFAULT_TAG := latest

.PHONY: build-image
build-image:
	$(DOCKER_BIN) build -t $(IMAGE_NAME):$(DEFAULT_TAG) .
