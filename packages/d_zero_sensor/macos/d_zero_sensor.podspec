Pod::Spec.new do |s|
  s.name             = 'd_zero_sensor'
  s.version          = '0.1.6'
  s.summary          = 'Zero-allocation C++17 FFI camera scanner and sensor widgets for Flutter.'
  s.description      = <<-DESC
Zero-allocation C++17 Seqlock shared-memory YUV420 camera scanner and sensor widgets for Flutter Impeller.
                       DESC
  s.homepage         = 'https://github.com/ANIZA15/D-Zero/tree/main/packages/d_zero_sensor'
  s.license          = { :type => 'MIT' }
  s.author           = { 'fexcy' => 'pakukotaro0105@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m,mm,swift}', '../src/**/*.{h,cpp}'
  s.public_header_files = 'Classes/**/*.h', '../src/**/*.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.frameworks = 'AVFoundation', 'CoreMedia', 'CoreVideo', 'Vision', 'QuartzCore', 'AppKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
end
