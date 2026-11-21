APP = .build/黑猫桌宠.app
CORE = Sources/BlackCat.swift Sources/BlackCatBehavior.swift
SOURCES = Sources/main.swift $(CORE)
FLAGS = -O -target $(shell uname -m)-apple-macos13.0

.PHONY: app test
app: $(APP)/Contents/_CodeSignature/CodeResources

$(APP)/Contents/_CodeSignature/CodeResources: $(SOURCES) Resources/Info.plist Makefile
	mkdir -p "$(APP)/Contents/MacOS"
	swiftc $(FLAGS) $(SOURCES) -o "$(APP)/Contents/MacOS/MilkCat"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

test:
	mkdir -p .build
	swiftc $(FLAGS) $(CORE) Tests/CheckCatBehavior.swift -o .build/check
	.build/check
	swiftc $(FLAGS) -D VERIFY $(SOURCES) -o .build/verify
	.build/verify
