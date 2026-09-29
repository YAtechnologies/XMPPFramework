# XMPPFramework Changelog

## [0.1.2]
### Fixed
  - Capped `CocoaLumberjack` below `3.10.0`. That release raises its own minimum deployment target to iOS 15, which this package (iOS 9) cannot satisfy, so every consumer resolving it failed to build with `The package product 'CocoaLumberjack' requires minimum platform version 15.0 for the iOS platform, but this target supports 12.0`.

## [0.1.1]
### Fixed
  - Resolved an issue with `Package.swift` being included in sources, which caused issues in Tuist-based projects. [#2](https://github.com/YAtechnologies/XMPPFramework/pull/2)

## 0.1.0
  - Stable version from master branch 
