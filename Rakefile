require 'xcodeproj'

RUST_LIB_DIR = File.expand_path('lib', __dir__)
RUST_CLI_DIR = File.expand_path('cli', __dir__)
RUST_TARGET_DIR = File.join(RUST_LIB_DIR, 'target')
XCODE_PROJECT_PATH = File.expand_path('ui/mac/Vault0.xcodeproj', __dir__)
FRAMEWORKS_DIR = File.expand_path('ui/mac/Vault0/Frameworks', __dir__)

RUST_CRATE_NAME = 'vault0'
RUST_LIB_NAME = 'vault0'
RUST_STATIC_LIB = "lib#{RUST_LIB_NAME}.a"
HEADER_FILE = 'vault0.h'

task :build_rust_debug do
  puts 'Building Rust library (debug)...'
  Dir.chdir(RUST_LIB_DIR) do
    sh 'cargo build'
  end
end

task :build_rust_release do
  puts 'Building Rust library (release)...'
  Dir.chdir(RUST_LIB_DIR) do
    sh 'cargo build --release'
  end
end

task :generate_header do
  puts 'Generating C header file...'
  Dir.chdir(RUST_LIB_DIR) do
    sh "cbindgen --quiet --config cbindgen.toml --crate #{RUST_CRATE_NAME} --output #{HEADER_FILE}"
  end
end

task :configure_xcode do
  puts 'Configuring Xcode project...'

  project = Xcodeproj::Project.open(XCODE_PROJECT_PATH)

  rust_lib_path_debug = '$(PROJECT_DIR)/../../lib/target/debug'
  rust_lib_path_release = '$(PROJECT_DIR)/../../lib/target/release'
  rust_header_path = '$(PROJECT_DIR)/../../lib'
  frameworks_path = '$(PROJECT_DIR)/Vault0/Frameworks'
  project.targets.each do |target|
    puts "  Updating target: #{target.name}"

    target.build_configurations.each do |config|
      search_paths = config.build_settings['LIBRARY_SEARCH_PATHS'] || []
      search_paths = [search_paths] unless search_paths.is_a?(Array)

      rust_path = config.name == 'Release' ? rust_lib_path_release : rust_lib_path_debug
      old_paths_removed = false
      search_paths = search_paths.reject do |path|
        if path.to_s.include?('lib/target')
          old_paths_removed = true
          true
        else
          false
        end
      end
      puts "    Removed old vault0 paths from #{config.name}" if old_paths_removed

      search_paths << rust_path
      puts "    Added #{rust_path} to #{config.name} LIBRARY_SEARCH_PATHS"

      unless search_paths.include?(frameworks_path)
        search_paths << frameworks_path
      end

      config.build_settings['LIBRARY_SEARCH_PATHS'] = search_paths

      linker_flags = config.build_settings['OTHER_LINKER_FLAGS'] || ''
      unless linker_flags.include?("-l#{RUST_LIB_NAME}")
        config.build_settings['OTHER_LINKER_FLAGS'] = "#{linker_flags} -l#{RUST_LIB_NAME}".strip
        puts "    Added -l#{RUST_LIB_NAME} to #{config.name} OTHER_LINKER_FLAGS"
      end

      header_paths = config.build_settings['HEADER_SEARCH_PATHS'] || []
      header_paths = [header_paths] unless header_paths.is_a?(Array)
      old_header_removed = false
      header_paths = header_paths.reject do |path|
        if path.to_s.include?('Vault0/Frameworks')
          old_header_removed = true
          true
        else
          false
        end
      end
      puts "    Removed old Frameworks path from #{config.name} HEADER_SEARCH_PATHS" if old_header_removed

      unless header_paths.include?(rust_header_path)
        header_paths << rust_header_path
        puts "    Added #{rust_header_path} to #{config.name} HEADER_SEARCH_PATHS"
      end

      config.build_settings['HEADER_SEARCH_PATHS'] = header_paths
    end
  end

  project.save
end

# Public tasks

desc 'Initial setup: configure Xcode and generate header file'
task :setup => [:configure_xcode, :generate_header] do
  puts ''
  puts '✅ Setup complete!'
end

namespace :build do
  desc 'Build Rust library (debug build)'
  task :lib => [:build_rust_debug, :generate_header] do
    puts '✅ Rust library built (debug)'
  end
end

desc 'Build complete macOS app (release build)'
task :release => [:build_rust_release, :generate_header] do
  puts 'Building macOS app (Release)...'
  Dir.chdir(File.expand_path('ui/mac', __dir__)) do
    sh 'xcodebuild -project Vault0.xcodeproj -scheme Vault0 -configuration Release clean build'
  end
  puts ''
  puts '✅ Release build complete!'
  puts ''
  puts 'Location:'
  puts '  ~/Library/Developer/Xcode/DerivedData/Vault0-*/Build/Products/Release/Vault0.app'
end

desc 'Format code (Rust + Swift)'
task :format do
  puts 'Formatting Rust code...'
  Dir.chdir(RUST_LIB_DIR) do
    sh 'cargo fmt'
  end
  Dir.chdir(RUST_CLI_DIR) do
    sh 'cargo fmt'
  end

  puts 'Formatting Swift code...'
  Dir.chdir(File.expand_path('ui/mac', __dir__)) do
    sh 'swiftformat .'
  end

  puts '✅ Code formatted'
end

desc 'Clean Rust build artifacts'
task :clean do
  puts 'Cleaning Rust build artifacts...'
  Dir.chdir(RUST_LIB_DIR) do
    sh 'cargo clean'
  end
  puts '✅ Clean complete'
end

task :default do
  puts 'Vault0 Build System'
  puts ''
  puts 'Available commands:'
  puts '  rake setup       # Initial setup (configure Xcode + generate header)'
  puts '  rake build:lib   # Build Rust library (debug build)'
  puts '  rake release     # Build complete macOS app (release build)'
  puts '  rake format      # Format code (Rust + Swift)'
  puts '  rake clean       # Clean Rust build artifacts'
  puts ''
  puts 'Run "rake -T" for more details'
end
