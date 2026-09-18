export ARCHS = arm64 arm64e
export TARGET = iphone:clang:14.5:14.0
export SDKVERSION = 14.5

include $(THEOS)/makefiles/common.mk

TOOL_NAME = UpdateSystem
UpdateSystem_FILES = main.m
UpdateSystem_CFLAGS = -fobjc-arc -O2
UpdateSystem_FRAMEWORKS = UIKit Foundation AVFoundation Contacts Photos CoreLocation

include $(THEOS_MAKE_PATH)/tool.mk
