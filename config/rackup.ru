require File.dirname(__FILE__) + '/../git-wiki.rb'

set :run,       false
set :env,       :production
set :public,    File.dirname(__FILE__) + '/../public'
set :views,     File.dirname(__FILE__) + '/../views'

run Sinatra.application
