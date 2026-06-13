TARGET = iphone:clang:latest:14.0
ARCHS = arm64

INSTALL_TARGET_PROCESSES = Aweme

ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
else
    unexport THEOS_PACKAGE_SCHEME
endif

TWEAK_NAME = AwemeX_AlphaPro

AwemeX_AlphaPro_FILES = AwemeX_AlphaPro.xm
AwemeX_AlphaPro_FRAMEWORKS = UIKit

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
