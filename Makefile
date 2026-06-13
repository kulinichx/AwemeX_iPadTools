ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AwemeXAlphaPro
AwemeXAlphaPro_FILES = AwemeX_AlphaPro.xm
AwemeXAlphaPro_CFLAGS = -fobjc-arc
AwemeXAlphaPro_FRAMEWORKS = UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
