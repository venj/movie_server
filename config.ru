require 'rubygems'
require 'sinatra'

set :environment, ENV['RACK_ENV'].to_sym
disable :run, :reload

require File.join(File.dirname(__FILE__), 'app')

run Sinatra::Application
