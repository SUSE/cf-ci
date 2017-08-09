IMAGE ?= splatform/cf-ci-orchestration
TAG ?= latest

build:
	docker build -t ${IMAGE}:${TAG} - < Dockerfile

push: build
	docker push ${IMAGE}:${TAG}

.PHONY: build push
