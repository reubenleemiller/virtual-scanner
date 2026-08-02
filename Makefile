ifeq ($(origin CC),default)
CC := x86_64-w64-mingw32-g++
endif
TARGET ?=
CFLAGS ?= -O2 -Wall -Wextra -std=c++17
ARCH ?= x64
BUILD_DIR ?= build/$(ARCH)
LDFLAGS ?= -shared -static -static-libgcc -static-libstdc++ -Wl,--out-implib,$(BUILD_DIR)/libVirtualScanner.a

SRC := src/virtual_scanner.cpp src/VirtualScanner.def
OUT ?= $(BUILD_DIR)/VirtualScanner.ds

ifeq ($(TARGET),)
TARGET_FLAG :=
else
TARGET_FLAG := --target=$(TARGET)
endif

.PHONY: all clean

all: $(OUT)

$(OUT): $(SRC) src/twain_min.h
	mkdir -p $(BUILD_DIR)
	$(CC) $(TARGET_FLAG) $(CFLAGS) -o $@ $(SRC) $(LDFLAGS) -lgdi32 -lole32 -lshell32 -lwindowscodecs -luuid

clean:
	rm -rf build
