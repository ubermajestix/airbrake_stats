# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "airbrake_stats/version"

Gem::Specification.new do |s|
  s.name        = "airbrake_stats"
  s.version     = AirbrakeStats::VERSION
  s.authors     = ["Tyler Montgomery"]
  s.email       = ["tyler.a.montgomery@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{Analyze Airbrake Errors}
  s.description = %q{Pass in an Airbrake id to visualize and diagnose errors better.}

  s.rubyforge_project = "airbrake_stats"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
   s.add_runtime_dependency "map"
   s.add_runtime_dependency "nokogiri"
   s.add_runtime_dependency "http"
end
