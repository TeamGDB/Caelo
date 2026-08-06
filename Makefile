VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -X github.com/TeamGDB/caelo-core/internal/version.Version=$(VERSION)

BUILD := build

.PHONY: all
all: probe dylib

.PHONY: probe
probe:
	go build -ldflags "$(LDFLAGS)" -o $(BUILD)/caelo-probe ./cmd/caelo-probe

# The desktop apps load this. -buildmode=c-shared also writes libcaelo.h, which
# is the authority on the FFI surface — the Dart bindings are written against
# it, so regenerate before changing them.
.PHONY: dylib
dylib:
	CGO_ENABLED=1 go build -buildmode=c-shared \
		-ldflags "$(LDFLAGS)" \
		-o $(BUILD)/libcaelo.dylib ./libcaelo

.PHONY: test
test:
	go test ./...

.PHONY: vet
vet:
	go vet ./...

.PHONY: clean
clean:
	rm -rf $(BUILD)
