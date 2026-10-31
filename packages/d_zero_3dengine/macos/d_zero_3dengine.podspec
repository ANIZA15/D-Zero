Pod::Spec.new do |s|
  s.name             = 'd_zero_3dengine'
  s.version          = '0.1.4'
  s.summary          = 'Zero-jank, zero-copy 3D game engine viewport with Nanite-style cluster culling and Ray Tracing for Flutter Impeller.'
  s.description      = <<-DESC
A low-level 3D rendering engine utilizing 128-byte FFI shared-memory, 144Hz/240Hz/Uncapped frame scheduling, Nanite-style meshlet DAG culling, and Metal/DX12 Ray Tracing.
                       DESC
  s.homepage         = 'https://github.com/ANIZA15/D-Zero/tree/main/packages/d_zero_3dengine'
  s.license          = { :type => 'MIT' }
  s.author           = { 'fexcy' => 'pakukotaro0105@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m,mm,swift}', '../src/**/*.{h,cpp}'
  s.public_header_files = 'Classes/**/*.h', '../src/**/*.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.frameworks = 'CoreVideo', 'CoreGraphics', 'Metal', 'QuartzCore', 'AppKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
end
