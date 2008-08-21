require File.dirname(__FILE__) + '/../git-wiki.rb'

set :run, false
set :env, :production

run Sinatra.application
