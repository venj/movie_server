require File.join(File.dirname(__FILE__), 'server')
set :environment, :production
run Sinatra::Application