TARGET = iphone:clang:latest:14.0
ARCHS = arm64

INSTALL_TARGET_PROCESSES = Aweme AwemeLite AwemeHD AwemePad AwemeIpad AwemeTablet

ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
else
    unexport THEOS_PACKAGE_SCHEME
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AwemeX_AlphaPro

AwemeX_AlphaPro_FILES = \
	AwemeX_AlphaPro.xm \
	AwemeXSettings.xm \
	AwemeXSettingsHelper.m \
	AwemeXCustomInputView.m

AwemeX_AlphaPro_FRAMEWORKS = UIKit Foundation QuartzCore
AwemeX_AlphaPro_CFLAGS = -fobjc-arc -w
AwemeX_AlphaPro_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	@rm -rf .theos packages
