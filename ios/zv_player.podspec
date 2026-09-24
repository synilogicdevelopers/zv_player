Pod::Spec.new do |s|
  s.name             = 'zv_player'
  s.version          = '0.1.4'
  s.summary          = 'ZV Player: AVPlayer-backed playback for the zv_player Flutter plugin.'
  s.description      = <<-DESC
Native playback for zv_player on iOS, built on AVFoundation. Renders through
AVPlayerLayer, exposes tracks and capabilities to Flutter, and supports
Picture-in-Picture via AVKit.
                       DESC
  s.homepage         = 'https://github.com/synilogicdevelopers/zv_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Synilogic' => 'synilogicdevelopers@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'zv_player/Sources/zv_player/**/*.swift'
  s.resource_bundles = {'zv_player_privacy' => ['zv_player/Sources/zv_player/PrivacyInfo.xcprivacy']}
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.frameworks = 'AVFoundation', 'AVKit'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
