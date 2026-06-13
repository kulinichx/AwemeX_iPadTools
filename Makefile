
TARGET = iphone:clang:latest:14.0
ARCHS = arm64

INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AwemeX_AlphaPro

AwemeX_AlphaPro_FILES = AwemeX_AlphaPro.xm
AwemeX_AlphaPro_FRAMEWORKS = UIKit
AwemeX_AlphaPro_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
