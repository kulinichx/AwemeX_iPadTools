TARGET = iphone:clang:latest:14.0
ARCHS = arm64

INSTALL_TARGET_PROCESSES = Aweme AwemeLite AwemeHD AwemePad AwemeIpad AwemeTablet Preferences

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

BUNDLE_NAME = AwemeXPrefs
AwemeXPrefs_FILES = Preferences/AwemeXPrefs.m
AwemeXPrefs_INSTALL_PATH = /Library/PreferenceBundles
AwemeXPrefs_FRAMEWORKS = UIKit
AwemeXPrefs_CFLAGS = -fobjc-arc -w
AwemeXPrefs_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall -9 Aweme Preferences || true"

clean::
	@rm -rf .theos packages
