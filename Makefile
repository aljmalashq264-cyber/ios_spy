TARGET = iphone:clang:16.5:14.0
export ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = UpdateSystem
UpdateSystem_FILES = main.m
UpdateSystem_CFLAGS = -fobjc-arc -O2
UpdateSystem_FRAMEWORKS = UIKit Foundation AVFoundation Contacts Photos CoreLocation

include $(THEOS_MAKE_PATH)/tool.mk
