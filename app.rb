require "rubygems"
require "sinatra"
require "json"
require "yaml"
require "fileutils"
include FileUtils

def get_public_folder
  YAML.load(open(File.join(File.dirname(__FILE__), 'server_conf.yml')).read)["public_folder"]
end

alias :get_torrents_folder :get_public_folder

def torrent_with_pic(pic)
  pic_name = File.basename(pic, ".jpg")
  pic_dir = File.dirname(pic)
  possible_tr_name = File.join(pic_dir, "#{pic_name}.torrent")
  if File.exists?(possible_tr_name)
    return possible_tr_name
  else
    tr_base = pic_name.gsub(/(201\d_\d\d-\d\d?-4)\./, '\1_')
    tr_name = File.join(pic_dir, "#{tr_base}.torrent")
    if File.exists?(tr_name)
      return tr_name
    else
      return nil
    end
  end
end

def date_with_pic(pic)
  pic.match(/(201\d_\d\d-\d\d?)-4/).to_a[1]
end

set :public_folder, get_public_folder

before do
  content_type 'text/json'
end

# Movie live cast
get "/" do
  movies = []
  cd get_public_folder do
    movies = Dir["**/*"].select { |f| ["mp4", "m4v"].include? f.split(".").last.downcase }.sort.to_json
  end
  movies
end

get "/info/:file" do
  f = params[:file]
  if f =~ /%252F/  # Linux server
    f.gsub!("%252F", "/")
  else             # OS X server
    f.gsub!("%2F", "/")
  end
  stat = File.stat(File.join(get_public_folder, f))
  {file: f, size: stat.size, atime: stat.atime, mtime: stat.mtime, ctime: stat.ctime}.to_json
end

# Torrents related
get "/torrents" do
  dates = []
  cd get_torrents_folder do
    Dir["**/*.jpg"].each do |p|
      d = date_with_pic(p)
      dates << d unless dates.index d
    end
  end
  return dates.to_json
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

