ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:13.0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AwemeX
AwemeX_FILES = AwemeX_AlphaPro.xm
AwemeX_CFLAGS = -fobjc-arc
AwemeX_FRAMEWORKS = UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
