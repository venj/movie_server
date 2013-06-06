require "rubygems"
require "sinatra"
require "json"
require "yaml"
require "fileutils"
include FileUtils

TORRENT_BATCH = 25

def get_torrents_folder
  YAML.load(open(File.join(File.dirname(__FILE__), 'server_conf.yml')).read)["torrents_folder"]
end

set :public_folder, get_torrents_folder

before do
  content_type 'text/json'
end

get "/torrents/:page" do
  page = params[:page].to_i
  return [] if page == 0
  torrents = []
  cd get_torrents_folder do
    torrents = Dir["*.jpg"][0 * page ... TORRENT_BATCH * page]
  end
  return torrents.to_json
end
