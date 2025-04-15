require_relative "lib/conntrack_exporter/version"

Gem::Specification.new do |spec|
  spec.name = "conntrack_exporter"
  spec.version = ConntrackExporter::VERSION
  spec.authors = ["Kasumi Hanazuki"]
  spec.email = ["kasumi@rollingapple.net"]

  spec.summary = "conntrack_exporter"
  spec.description = "conntrack_exporter"
  spec.homepage = "https://github.com/hanazuki/conntrack_exporter"
  spec.license = "MIT AND BSD-3-Clause"
  spec.required_ruby_version = ">= 3.3.0"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "puma"
  spec.add_dependency "sinatra"
  spec.add_dependency "ynl"
  spec.add_dependency "prometheus-client"

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
