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

before do
  content_type 'text/json'
end

get "/" do
  movies = []
  cd get_public_folder do
    movies = Dir["**/*"].select { |f| ["mp4", "m4v"].include? f.split(".").last.downcase }.sort.to_json
  end
  movies
end

get "/info/:file" do
  f = params[:file].gsub("%2F", "/")
  stat = File.stat(File.join(get_public_folder, f))
  {file: f, size: stat.size, atime: stat.atime, mtime: stat.mtime, ctime: stat.ctime}.to_json
end
