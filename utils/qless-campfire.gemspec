$LOAD_PATH.push File.expand_path('../lib', __dir__)
require 'qless/version'

Gem::Specification.new do |s|
  s.name        = 'qless-campfire'
  s.version     = Qless::VERSION
  s.authors     = ['Dan Lecocq']
  s.email       = ['dan@seomoz.org']
  s.homepage    = 'http://github.com/seomoz/qless'
  s.summary     = 'Campfire Notifications for Qless'
  s.description = "
    Get Campfire notifications for jobs you're tracking in your qless
    queue.
  "

  s.rubyforge_project = 'qless-campfire'

  s.files         = Dir.glob('exe/qless-campfire')
  s.bindir        = 'exe'
  s.executables   = ['qless-campfire']

  s.add_dependency 'micro-optparse', '~> 1.1'
  s.add_dependency 'qless', '~> 0.9'
  s.add_dependency 'tinder', '~> 1.8'
end
