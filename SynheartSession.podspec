Pod::Spec.new do |spec|
  spec.name         = "SynheartSession"
  spec.version      = "0.2.1"
  spec.summary      = "Real-time wearable HR session capture for iOS"
  spec.homepage     = "https://github.com/synheart-ai/synheart-session-swift"
  spec.license      = { :type => "Apache-2.0", :file => "LICENSE" }
  spec.author       = { "Synheart AI" => "dev@synheart.ai" }
  spec.ios.deployment_target = "13.0"
  spec.osx.deployment_target = "10.15"
  spec.watchos.deployment_target = "6.0"
  spec.tvos.deployment_target = "13.0"
  spec.source       = { :git => "https://github.com/synheart-ai/synheart-session-swift.git", :tag => "v#{spec.version}" }
  spec.source_files = "Sources/SynheartSession/**/*.swift"
  spec.swift_version = "5.9"
  spec.requires_arc = true
end
