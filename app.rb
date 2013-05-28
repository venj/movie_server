require "rubygems"
require "sinatra"
require "json"
require "yaml"
require "fileutils"
include FileUtils

def get_public_folder
  YAML.load(open(File.join(File.dirname(__FILE__), 'server_conf.yml')).read)["public_folder"]
end

set :public_folder, get_public_folder

get "/" do
  content_type 'application/json'
  movies = []
  cd get_public_folder do
    movies = Dir["**/*"].select { |f| ["mp4", "m4v"].include? f.split(".").last.downcase }.sort.to_json
  end
  movies
end
