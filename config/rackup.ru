require File.dirname(__FILE__) + '/../git-wiki.rb'

set :run, false
set :env, ENV['APP_ENV'] || :development

run Sinatra.application
