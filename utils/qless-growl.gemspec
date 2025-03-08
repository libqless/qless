$LOAD_PATH.push File.expand_path('../lib', __dir__)
require 'qless/version'

Gem::Specification.new do |s|
  s.name        = 'qless-growl'
  s.version     = Qless::VERSION
  s.authors     = ['Dan Lecocq']
  s.email       = ['dan@seomoz.org']
  s.homepage    = 'http://github.com/seomoz/qless'
  s.summary     = 'Growl Notifications for Qless'
  s.description = "
    Get Growl notifications for jobs you're tracking in your qless
    queue.
  "

  s.rubyforge_project = 'qless-growl'

  s.files         = Dir.glob('exe/qless-growl')
  s.bindir        = 'exe'
  s.executables   = ['qless-growl']

  s.add_dependency 'micro-optparse', '~> 1.1'
  s.add_dependency 'qless', '~> 0.9'
  s.add_dependency 'ruby-growl', '~> 4.0'
end
