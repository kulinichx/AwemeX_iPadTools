TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME := AwemeX_iPadCompat
AwemeX_iPadCompat_FILES := AwemeX_iPadCompat.c
AwemeX_iPadCompat_CFLAGS := -O2 -fvisibility=hidden -Wall -Wextra -Wno-cast-function-type-mismatch
AwemeX_iPadCompat_LDFLAGS := -Wl,-install_name,@loader_path/AwemeX_iPadCompat.dylib -lobjc -ldispatch

include $(THEOS_MAKE_PATH)/library.mk
