ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME=rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME=roothide
endif

DEBUG=0
FINALPACKAGE=1
ARCHS = arm64
TARGET := iphone:clang:16.5:13.0
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTYandexTranslate
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AVFoundation
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FILES = YTYandexTranslate.x YTLYandexTranslationFetcher.m

include $(THEOS_MAKE_PATH)/tweak.mk
