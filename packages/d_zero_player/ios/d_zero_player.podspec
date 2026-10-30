Pod::Spec.new do |s|
  s.name             = 'd_zero_player'
  s.version          = '0.1.0'
  s.summary          = 'Zero-jank, zero-copy next-gen video player for Flutter Impeller.'
  s.description      = <<-DESC
A next-generation video player utilizing FFI shared-memory and Impeller-optimized zero-copy textures.
                       DESC
  s.homepage         = 'https://github.com/ANIZA15/D-Zero/tree/main/packages/d_zero_player'
  s.license          = { :type => 'MIT' }
  s.author           = { 'fexcy' => 'contact@fexcy.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m,mm,swift}', '../src/**/*.{h,cpp}'
  s.public_header_files = 'Classes/**/*.h', '../src/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'AVFoundation', 'CoreVideo', 'Metal'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
end
