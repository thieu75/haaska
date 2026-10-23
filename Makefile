SHELL := /bin/bash

# Function name in AWS Lambda:
FUNCTION_NAME=haaska

# Lambda runtime and architecture, dependencies are fetched for this target
# so the zip works on Lambda whatever the build machine is.
RUNTIME=python3.13
PYTHON_VERSION=3.13
PLATFORM=manylinux2014_x86_64

BUILD_DIR=build

haaska.zip: haaska.py config/config.json requirements.txt
	rm -rf $(BUILD_DIR) $@
	mkdir -p $(BUILD_DIR)
	cp haaska.py config/config.json $(BUILD_DIR)
	pip3 install -t $(BUILD_DIR) -r requirements.txt \
		--platform $(PLATFORM) --python-version $(PYTHON_VERSION) \
		--implementation cp --only-binary=:all:
	chmod 755 $(BUILD_DIR)/haaska.py
	cd $(BUILD_DIR); zip ../$@ -r *

.PHONY: deploy
deploy: haaska.zip
	aws lambda update-function-configuration \
		--function-name $(FUNCTION_NAME) \
		--runtime $(RUNTIME) \
		--handler haaska.event_handler
	aws lambda wait function-updated --function-name $(FUNCTION_NAME)
	aws lambda update-function-code \
		--function-name $(FUNCTION_NAME) \
		--zip-file fileb://$<

DISCOVERY_PAYLOAD:='                                \
{                                                         \
  "directive": {                                          \
    "header": {                                           \
      "namespace": "Alexa.Discovery",                     \
      "name": "Discover",                                 \
      "payloadVersion": "3",                              \
      "messageId": "1bd5d003-31b9-476f-ad03-71d471922820" \
    },                                                    \
    "payload": {                                          \
      "scope": {                                          \
        "type": "BearerToken",                            \
        "token": "access-token-from-skill"                \
      }                                                   \
    }                                                     \
  }                                                       \
}'

.PHONY: discover
discover:
	@aws lambda invoke \
		--function-name $(FUNCTION_NAME) \
		--cli-binary-format raw-in-base64-out \
		--payload ${DISCOVERY_PAYLOAD} \
		/dev/fd/3 3>&1 >/dev/null | jq '.'

.PHONY: test
test:
	python3 -m pytest test.py
	flake8 haaska.py test.py

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) haaska.zip
