VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -X github.com/TeamGDB/Caelo/core/internal/version.Version=$(VERSION)

BUILD := build

# The shared library is named for what each platform's loader expects to find,
# which is why nothing on the Dart side ever builds a path.
.PHONY: lib
lib:
	@case "$$(go env GOOS)" in \
	  darwin)  $(MAKE) macos ;; \
	  linux)   $(MAKE) linux ;; \
	  windows) $(MAKE) windows ;; \
	  *) echo "no library target for $$(go env GOOS)" >&2; exit 1 ;; \
	esac

# Universal, not host-only. A dylib built on an Apple Silicon machine will not
# load on an Intel one, and that failure happens at the user rather than at us.
.PHONY: macos
macos:
	CGO_ENABLED=1 GOARCH=arm64 go build -buildmode=c-shared \
		-ldflags "$(LDFLAGS)" -o $(BUILD)/libcaelo-arm64.dylib ./libcaelo
	CGO_ENABLED=1 GOARCH=amd64 go build -buildmode=c-shared \
		-ldflags "$(LDFLAGS)" -o $(BUILD)/libcaelo-amd64.dylib ./libcaelo
	lipo -create -output $(BUILD)/libcaelo.dylib \
		$(BUILD)/libcaelo-arm64.dylib $(BUILD)/libcaelo-amd64.dylib
	@rm -f $(BUILD)/libcaelo-amd64.h
	@mv $(BUILD)/libcaelo-arm64.h $(BUILD)/libcaelo.h
	@rm -f $(BUILD)/libcaelo-arm64.dylib $(BUILD)/libcaelo-amd64.dylib
	@lipo -info $(BUILD)/libcaelo.dylib

# Kept as an alias: scripts and muscle memory both point at it.
.PHONY: dylib
dylib: macos

# A static archive for the macOS system extension. A system extension has its
# own ideas about where libraries live, and linking the core in rather than
# alongside removes the question entirely — the same trade already made on iOS.
#
# The generated header is kept, not swept up with the per-architecture leavings:
# the Swift bridging header includes it. Deleting it worked on every machine
# that had ever run `make macos` and on no CI runner.
.PHONY: macos-static
macos-static:
	CGO_ENABLED=1 GOARCH=arm64 go build -buildmode=c-archive \
		-ldflags "$(LDFLAGS)" -o $(BUILD)/libcaelo-static-arm64.a ./libcaelo
	CGO_ENABLED=1 GOARCH=amd64 go build -buildmode=c-archive \
		-ldflags "$(LDFLAGS)" -o $(BUILD)/libcaelo-static-amd64.a ./libcaelo
	lipo -create -output $(BUILD)/libcaelo.a \
		$(BUILD)/libcaelo-static-arm64.a $(BUILD)/libcaelo-static-amd64.a
	@rm -f $(BUILD)/libcaelo-static-amd64.h
	@mv $(BUILD)/libcaelo-static-arm64.h $(BUILD)/libcaelo.h
	@rm -f $(BUILD)/libcaelo-static-arm64.a $(BUILD)/libcaelo-static-amd64.a
	@lipo -info $(BUILD)/libcaelo.a

.PHONY: linux
linux:
	CGO_ENABLED=1 go build -buildmode=c-shared \
		-ldflags "$(LDFLAGS)" -o $(BUILD)/libcaelo.so ./libcaelo

# Cross-compiling this needs mingw-w64; building it on Windows needs nothing
# beyond a C compiler, which is why CI does it on a Windows runner.
.PHONY: windows
windows:
	CGO_ENABLED=1 GOOS=windows GOARCH=amd64 go build -buildmode=c-shared \
		-ldflags "$(LDFLAGS)" -o $(BUILD)/caelo.dll ./libcaelo

.PHONY: android
android:
	./deploy/android/build-so.sh $(BUILD)/android

.PHONY: ios
ios:
	./deploy/ios/build-xcframework.sh

.PHONY: probe
probe:
	go build -ldflags "$(LDFLAGS)" -o $(BUILD)/caelo-probe ./cmd/caelo-probe

# Routes the whole machine. Needs root to run, not to build. macOS and Linux.
.PHONY: tun
tun:
	go build -ldflags "$(LDFLAGS)" -o $(BUILD)/caelo-tun ./cmd/caelo-tun

.PHONY: test
test:
	go test ./...

.PHONY: vet
vet:
	go vet ./...

.PHONY: clean
clean:
	rm -rf $(BUILD)
