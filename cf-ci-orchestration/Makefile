IMAGE ?= splatform/cf-ci-orchestration
TAG ?= cap2

build:
	docker build -t ${IMAGE}:${TAG} .

push: build
	docker push ${IMAGE}:${TAG}

.PHONY: build push
