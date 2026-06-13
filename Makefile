TARGET = iphone:clang:latest:14.0
ARCHS = arm64

INSTALL_TARGET_PROCESSES = Aweme

ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
else
    unexport THEOS_PACKAGE_SCHEME
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AwemeX_AlphaPro

AwemeX_AlphaPro_FILES = AwemeX_AlphaPro.xm
AwemeX_AlphaPro_FRAMEWORKS = UIKit Foundation QuartzCore
AwemeX_AlphaPro_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	@rm -rf .theos packages
