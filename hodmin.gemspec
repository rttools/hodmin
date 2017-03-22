# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hodmin/version'

Gem::Specification.new do |spec|
  spec.name          = "hodmin"
  spec.version       = Hodmin::VERSION
  spec.authors       = ["Thomas Romeyke"]
  spec.email         = ["rttools@googlemail.com"]
  spec.licenses      = ['GPL-3.0']

  spec.summary       = %q{Hodmin is a tool to administrate Homie-devices (esp8266-based microcomputers with Homie-firmware)}
  spec.description   = %q{Hodmin enables you to administrate your Homie-devices via command-line-interface (CLI). It consists of some scripts to wrap homie-administration in some handy commands. Hodmin does not communicate with a homie-device directly. It instead uses your MQTT-broker to pass informations to a device.}
  spec.homepage      = "http://www.github.com/rttools/hodmin"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "http://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  #spec.files         = `git ls-files -z`.split("\x0").reject do |f|
  #  f.match(%r{^(test|spec|features)/})
  #end
  spec.files         = ['lib/hodmin/hodmin_initialize.rb', 'lib/hodmin/hodmin_pull_config.rb', 'lib/hodmin/hodmin_push_firmware.rb', \
                       'lib/hodmin/hodmin_rename.rb', 'lib/hodmin/version.rb', 'lib/hodmin/hodmin_list.rb', 'lib/hodmin/hodmin_push_config.rb',\
                       'lib/hodmin/hodmin_remove.rb', 'lib/hodmin/hodmin_tools.rb', 'lib/hodmin.rb']
  spec.bindir        = "bin"
  spec.executables   = ["hodmin"]
  spec.require_paths = ["lib"]

  spec.add_dependency 'configatron', '~> 4.5', '>= 4.5.0'
  spec.add_dependency 'mqtt', '~> 0.4.0'
  spec.add_dependency 'pastel', '~> 0.7.1'
  spec.add_dependency 'trollop', '~> 2.1', '>= 2.1.2'
  spec.add_dependency 'tty-cursor', '>= 0.4.0'
  spec.add_dependency 'tty-table', '>= 0.7.0'

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
