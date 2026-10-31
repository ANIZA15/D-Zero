Pod::Spec.new do |s|
  s.name             = 'd_zero_terminal'
  s.version          = '0.1.4'
  s.summary          = 'Zero-allocation FFI PTY terminal emulator and ANSI/VT100 parser for Flutter Impeller.'
  s.description      = <<-DESC
Ultra-lightweight terminal emulator utilizing C++17 FFI shared-memory, zero-allocation VT100/TrueColor state machine, POSIX forkpty, and single-pass Impeller drawRawAtlas rendering.
                       DESC
  s.homepage         = 'https://github.com/ANIZA15/D-Zero/tree/main/packages/d_zero_terminal'
  s.license          = { :type => 'MIT' }
  s.author           = { 'fexcy' => 'pakukotaro0105@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m,mm,swift}', '../src/**/*.{h,cpp}'
  s.public_header_files = 'Classes/**/*.h', '../src/**/*.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.frameworks = 'AppKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
end
