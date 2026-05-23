BINARY     := oled
MAIN       := main_auto.go
GOARCH     := arm64
GOOS       := linux
CGO        := 0
LDFLAGS    := -s -w
GOPROXY    ?= https://goproxy.cn,direct
SSH_HOST   ?= root@192.168.10.107
REMOTE_DIR := /usr/local/oled

.PHONY: all build upload deploy full-deploy restart test clean

all: build

build:
	@echo "=> Building $(BINARY) for $(GOOS)/$(GOARCH)..."
	CGO_ENABLED=$(CGO) GOARCH=$(GOARCH) GOOS=$(GOOS) GOPROXY=$(GOPROXY) \
		go build -ldflags="$(LDFLAGS)" -o $(BINARY) $(MAIN)
	@echo "=> Built: $(BINARY)"

upload:
	@echo "=> Uploading $(BINARY) to $(SSH_HOST):$(REMOTE_DIR)/"
	scp $(BINARY) $(SSH_HOST):$(REMOTE_DIR)/

deploy: build upload
	@echo "=> Deploying on remote..."
	ssh $(SSH_HOST) '\
		systemctl stop oled.service 2>/dev/null; \
		killall -9 oled 2>/dev/null; \
		sleep 1; \
		systemctl start oled.service; \
		sleep 1; \
		echo "=> Deploy done"; \
		systemctl status oled.service --no-pager -l'

full-deploy: build upload
	@echo "=> Full deploy (binary + service + init script)..."
	scp ../../etc/systemd/system/oled.service $(SSH_HOST):/etc/systemd/system/oled.service
	scp oled_init.sh $(SSH_HOST):$(REMOTE_DIR)/oled_init.sh
	ssh $(SSH_HOST) '\
		chmod +x $(REMOTE_DIR)/oled_init.sh; \
		systemctl daemon-reload; \
		systemctl stop oled.service 2>/dev/null; \
		killall -9 oled 2>/dev/null; \
		sleep 1; \
		systemctl start oled.service; \
		sleep 1; \
		echo "=> Full deploy done"; \
		systemctl status oled.service --no-pager -l'

restart:
	ssh $(SSH_HOST) 'systemctl restart oled.service'

test:
	ssh $(SSH_HOST) '\
		systemctl stop oled.service 2>/dev/null; \
		killall -9 oled 2>/dev/null; \
		sleep 1; \
		echo "=== Running $(BINARY) foreground ==="; \
		timeout 15 $(REMOTE_DIR)/$(BINARY) 2>&1; \
		echo "=== Done, restarting service ==="; \
		systemctl start oled.service'

clean:
	rm -f $(BINARY)
