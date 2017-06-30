IMAGE ?= splatform/opensuse-kubectl
TAG ?= latest

build:
	docker build -t ${IMAGE}:${TAG} - < Dockerfile

push: build
	docker push ${IMAGE}:${TAG}