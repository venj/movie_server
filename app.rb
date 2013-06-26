#!/usr/bin/env ruby
#encoding = UTF-8
require "rubygems"
require "sinatra"
require "json"
require "yaml"
require "shellwords"
require "fileutils"
include FileUtils

def get_public_folder
  YAML.load(open(File.join(File.dirname(__FILE__), 'server_conf.yml')).read)["public_folder"]
end

def get_lx_command
  YAML.load(open(File.join(File.dirname(__FILE__), 'server_conf.yml')).read)["lixian_command"]
end

alias :get_torrents_folder :get_public_folder

def torrent_with_pic(pic)
  pic_name = File.basename(pic, ".jpg")
  pic_dir = File.dirname(pic)
  tr_name_1 = File.join(pic_dir, "#{pic_name}.torrent")
  frags = pic.split("_");frags.pop
  tr_name_2 = "#{frags.join("_")}.torrent"
  puts tr_name_1
  if File.exists?(tr_name_1)
    return tr_name_1
  elsif File.exists?(tr_name_2)
    return tr_name_2
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
  pic.match(/(201\d_\d\d-\d\d?)/).to_a[1] || pic.match(/(\[\d\-\d\d\]最新BT合集)/).to_a[1]
end

set :public_folder, get_public_folder

before do
  content_type 'text/json'
end

# Movie live cast
get "/" do
  movies = []
  cd get_public_folder do
    movies = Dir["**/*"].select { |f| ["mp4", "m4v", "mov"].include? f.split(".").last.downcase }.sort.to_json
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

delete "/remove/:file" do
  f = params[:file]
  if f =~ /%252F/  # Linux server
    f.gsub!("%252F", "/")
  else             # OS X server
    f.gsub!("%2F", "/")
  end
  cd get_public_folder do
    if File.exists?(f)
      %x["rm -f #{f}".shellescape]
    end
  end
  {status: "done"}.to_json
end

# Torrents related
get "/torrents" do
  dates = []
  tr_folder = get_torrents_folder
  cd tr_folder do
    Dir["**/*.jpg"].each do |p|
      d = date_with_pic(p)
      dates << d unless dates.index d
    end
  end
  dates.compact! # Why the trailing nil?
  return dates.sort { |x, y| (x.index("[") != y.index("[")) ? (x <=> y) * -1 : x <=> y }.reverse.to_json
end

get "/search/:keyword" do
  keyword = params[:keyword]
  pics = []
  cd get_torrents_folder do
    pics = Dir["**/*.jpg"].select { |f| f.index keyword }
  end
  return pics.to_json
end

get "/lx/:file/:async" do
  f = params[:file]
  if f =~ /%252F/  # Linux server
    f.gsub!("%252F", "/")
  else             # OS X server
    f.gsub!("%2F", "/")
  end
  lx_command = get_lx_command
  cd get_torrents_folder do
    if params[:async] == "1"
      fork {
        exec "#{lx_command} add #{torrent_with_pic f}"
      }
      return {status: "done"}.to_json
    elsif params[:async] == "0"
      result = %x[#{lx_command} add #{torrent_with_pic f}]
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
end
