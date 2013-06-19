require "rubygems"
require "sinatra"
require "json"
require "yaml"
require "fileutils"
include FileUtils

def get_torrents_folder
  YAML.load(open(File.join(File.dirname(__FILE__), 'server_conf.yml')).read)["torrents_folder"]
end

def torrent_with_pic(pic)
  pic_name = File.basename(pic, ".jpg")
  pic_dir = File.dirname(pic)
  possible_tr_name = File.join(pic_dir, "#{pic_name}.torrent")
  if File.exists?(possible_tr_name)
    return possible_tr_name
  else
    tr_base = pic_name.gsub(/(201\d_\d\d-\d\d?-?\d?)\./, '\1_')
    tr_name = File.join(pic_dir, "#{tr_base}.torrent")
    if File.exists?(tr_name)
      return tr_name
    else
      return nil
    end
  end
end

def date_with_pic(pic)
  pic.match(/(201\d_\d\d-\d\d?)/).to_a[1]
end

set :public_folder, get_torrents_folder

before do
  content_type 'text/json'
end

get "/torrents" do
  dates = []
  cd get_torrents_folder do
    Dir["**/*.jpg"].each do |p|
      d = date_with_pic(p)
      dates << d unless (dates.index d && d)
    end
  end
  dates.compact! # Why the trailing nil? 
  return dates.sort.reverse.to_json
end

get "/search/:keyword" do
  keyword = params[:keyword]
  pics = []
  cd get_torrents_folder do
    pics = Dir["**/*.jpg"].select { |f| f.index keyword }
  end
  return pics.to_json
end

get "/lx/:file" do
  f = params[:file]
  if f =~ /%252F/  # Linux server
    f.gsub!("%252F", "/")
  else             # OS X server
    f.gsub!("%2F", "/")
  end
  cd get_torrents_folder do
    result = %x[/usr/local/bin/my lx add #{torrent_with_pic f}]
    if result =~ /completed/
      status = "completed"
    elsif result =~ /waiting/
      status = "waiting"
    elsif result =~ /downloading/
      status = "downloading"
    else
      status = "failed or unknown"
    end
    return {status: status}.to_json
  end
end

