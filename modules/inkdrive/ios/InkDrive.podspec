Pod::Spec.new do |s|
  s.name = 'InkDrive'
  s.module_name = 'InkDriveNative'
  s.version = '0.1.0'
  s.summary = 'In-place PencilKit PDF editor'
  s.description = 'Local-only Expo module for security-scoped PDF editing.'
  s.license = { :type => 'Private' }
  s.author = 'InkDrive'
  s.homepage = 'https://localhost.invalid/inkdrive'
  s.platforms = { :ios => '17.0' }
  s.source = { :path => '.' }
  s.static_framework = true
  s.swift_version = '5.9'
  s.dependency 'ExpoModulesCore'
  s.frameworks = 'UIKit', 'PDFKit', 'PencilKit', 'UniformTypeIdentifiers', 'CryptoKit', 'AVFoundation'
  s.source_files = 'Core/**/*.swift', 'UI/**/*.swift', 'InkDriveModule.swift'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'SWIFT_STRICT_CONCURRENCY' => 'minimal' }
end
