#!/usr/bin/env ruby
#encoding = UTF-8
require "rubygems"
require "sinatra"
require "json"
require "yaml"
require "shellwords"
require "date"
require "fileutils"
require "sqlite3"
include FileUtils

class AppConfig
  def initialize
    @vars = YAML.load(open(File.join(File.dirname(__FILE__), 'server_conf.yml')).read)
  end
  
  def public_folder
    @vars["public_folder"]
  end
  
  def lx_command
    @vars["lixian_command"]
  end

  def lx_hash_command
    @vars["lixian_hash_command"]
  end
  
  def max_pic_size
    @vars["max_pic_size"].to_i * 1024
  end
  
  def relative_folders
    @vars["relative_folders"]
  end
  
  def default_sort?
    @vars["default_sort_order"]
  end
  
  def basic_auth_enabled?
    @vars["enable_basic_auth"]
  end
  
  def username
    @vars["auth"][0]
  end
  
  def password
    @vars["auth"][1]
  end

  def tr_db_path
    @vars["tr_db_path"]
  end
  
end

config = AppConfig.new

helpers do
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
        if is_windows
          return tr_name
        else
          return tr_name.shellescape
        end
      else
        return nil
      end
    end
  end

  def is_windows
    ENV['OS'] == "Windows_NT" ? true : false
  end

  def slash_process(file)
    f = file
    if f =~ /%252F/  # Linux server
      f.gsub!("%252F", "/")
    else             # OS X server
      f.gsub!("%2F", "/")
    end
  end

  def protected!
    return if authorized?
    headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
    halt 401, {status: "Not authorized"}.to_json
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    config = AppConfig.new
    @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == [config.username, config.password]
  end

  def db_search(keyword)
    config = AppConfig.new
    path = config.tr_db_path
    unless File.exists? path
      return { success: false, message: "No torrents db.", results:nil }.to_json
    end

    begin
      db = SQLite3::Database.new path
    rescue SQLite3::Exception => e 
      return { success: false, message: "Can not open file", results:nil }.to_json
    end

    trs = []
    db.execute "SELECT name, size, magnet FROM Torrents WHERE `name` LIKE '%#{keyword}%'" do |row|
      trs << {name: row[0], size: row[1], magnet: row[2]}
    end
    if trs.size > 0
      return { success: true, message: "Found #{trs.size} torrents", results:trs }.to_json
    else
      return { success: false, message: "No torrent found", results:nil }.to_json
    end
  end

end

def date_with_pic(pic)
  pic.match(/(201\d_\d\d-\d\d?)/).to_a[1] || pic.match(/(\[\d\-\d\d\]最新BT合(集)?)/).to_a[1]
end

set :public_folder, config.public_folder

before do
  content_type 'text/json'
  protected! if config.basic_auth_enabled?
end

# Movie live cast
get "/" do
  movies = []
  cd config.public_folder do
    movies = Dir["**/*"].select { |f| ["mp4", "m4v", "mov"].include?(f.split(".").last.downcase) and !File.directory?(f) }.sort.to_json
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
  cd config.public_folder do
    if File.exists?(f)
      stat = File.stat(File.join(config.public_folder, f))
      return {file: f, size: stat.size, atime: stat.atime, mtime: stat.mtime, ctime: stat.ctime, exist: true}.to_json
    else
      return {exist: false}.to_json
    end
  end
end

get "/db_search" do
  keyword = params[:keyword]
  return db_search(keyword)
end

delete "/remove/:file" do
  f = params[:file]
  if f =~ /%252F/  # Linux server
    f.gsub!("%252F", "/")
  else             # OS X server
    f.gsub!("%2F", "/")
  end
  cd config.public_folder do
    if File.exists?(f)
      rm_f (is_windows ? f : f.shellescape)
    end
  end
  {status: "done"}.to_json
end

# Torrents related
get "/torrents" do
  datelist = []
  folders = config.relative_folders
  cd config.public_folder do
    if File.exists?(folders[0])
      cd folders[0] do
        if File.exists?(".finished")
          regex = /(\d{4}\/\d{2}-\d{1,2})(-\d)?\/1\/$/
          selected = open(".finished").readlines.to_a.select { |u| u.strip =~ regex }
          datelist = selected.map { |u| regex.match(u)[1].gsub("/", "_") }.sort.reverse
        end
      end
    end
    if File.exists?(folders[1])
      cd folders[1] do
        list = Dir["**"].select{ |f| !(["SyncArchive", "tu.rb", "Icon?"].include?(f) or f =~ /Icon/) }.sort_by do |x|
          m = x[1...x.index(']')].split("-")
          [m.length, *m.map{|a|a.to_i}]
        end.reverse
        if config.default_sort?
          datelist = list + datelist
        else
          datelist += list
        end
      end
    end
  end
  return datelist.to_json
end

#get "/search/:keyword" do
get %r{/search/(.+)} do
  keyword = URI.unescape params[:captures].first
  #keyword = params[:keyword]
  pics = []
  max_pic_size = config.max_pic_size
  folders = config.relative_folders
  cd config.public_folder do
    if keyword.index("[")
      cd File.join(folders[1], keyword) do
        pics = Dir["*"].select do |f|
          if ["jpg", "gif", "png", "bmp", "jpeg"].index(f.split(".").last.downcase)
            File.stat(f).size < max_pic_size
          end
        end
        pics.map!{ |f| File.join(folders[1], keyword, f) }
      end
    else
      cd folders[0] do
        pics = Dir["**/*#{keyword}*"].select{ |f| ["jpg", "jpeg"].index(f.split(".").last.downcase) }.map{|f| File.join(folders[0], f)}
      end
    end
  end
  return pics.sort.to_json
end

get "/hash/:file" do
  f = slash_process(params[:file])
  lx_command = config.lx_command
  lx_hash_command = config.lx_hash_command
  cd config.public_folder do
    result = %x|#{lx_hash_command} #{torrent_with_pic f}|.split(" ")[0]
    return {hash: result.strip}.to_json
  end
end

get "/lx/:file/:async" do
  f = slash_process(params[:file])
  lx_command = config.lx_command
  cd config.public_folder do
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
      elsif result =~ /\[0976\]/
        status = "Oh no, 0976"
      elsif result =~ /Verification code required/
        status = "Oh no, code"
      else
        status = "failed or unknown"
      end
      return {status: status}.to_json
    end
  end
end
