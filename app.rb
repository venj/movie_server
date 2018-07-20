#!/usr/bin/env ruby
#encoding = UTF-8
require 'rubygems'
require 'sinatra'
require 'json'
require 'yaml'
require "shellwords"
require 'date'
require 'fileutils'
require 'sqlite3'
require 'base64'
require 'open-uri'
require 'active_support/all'
require 'bencode'
require 'digest/sha1'
require "uri"

include FileUtils

class AppConfig
  def initialize
    @vars = YAML.load(open(File.join(File.dirname(__FILE__), 'server_conf.yml')).read)
  end

  def max_pic_size
    @vars['max_pic_size'].to_i * 1024
  end

  def username
    @vars['auth'][0]
  end

  def password
    @vars['auth'][1]
  end

  def method_missing(m, *args, &block)
    method_name = m.to_s
    key = method_name.include?('?') ? method_name.chop : method_name
    value = @vars[key]
    return value unless value.nil?
    super
  end
end

config = AppConfig.new

if config.ssl_enabled
  require File.join(File.dirname(__FILE__), 'sinatra_ssl')
  set :ssl_certificate, config.ssl_cert_path
  set :ssl_key, config.ssl_key_path
  set :port, 8443
end

helpers do
  def torrent_with_pic(pic)
    tr_name = File.join(File.dirname(pic), "#{File.basename(pic, '.jpg').split('_').first}.torrent")
    if File.exists?(tr_name)
      return tr_name
    else
      return nil
    end
  end

  def is_windows
    ENV['OS'] == 'Windows_NT'? true : false
  end

  def slash_process(file)
    f = file
    if f =~ /%252F/  # Linux server
      f.gsub!('%252F', '/')
    else             # OS X server
      f.gsub!('2F', '/')
    end
  end

  def protected!
    return if authorized?
    headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
    halt 401, {status: 'Not authorized'}.to_json
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
      return { success: false, message: 'No torrents db.', results:nil }.to_json
    end

    if keyword.empty?
      return { success: false, message: 'Empty search keyword.', results:nil }.to_json
    end

    begin
      db = SQLite3::Database.new path
    rescue SQLite3::Exception => e
      return { success: false, message: 'Can not open file', results:nil }.to_json
    end

    trs = []
    db.execute "SELECT name, size, magnet, upload_date, seeders FROM torrents WHERE `name` LIKE '%#{keyword}%' ORDER BY upload_date DESC" do |row|
      trs << {name: row[0], size: row[1], magnet: row[2], upload_date: row[3].to_i, seeders: row[4] }
    end
    if trs.size > 0
      return { success: true, message: "Found #{trs.size} torrents", results:trs }.to_json
    else
      return { success: false, message: 'No torrent found', results:nil }.to_json
    end
  end

end

def date_with_pic(pic)
  pic.match(/(201\d_\d\d-\d\d?)/).to_a[1] || pic.match(/(\[\d\-\d\d\]最新BT合(集)?)/).to_a[1]
end

set :public_folder, config.public_folder

before do
  content_type 'text/json'
  protected! if config.enable_basic_auth?
  halt 401, {status: 'Not allowed.'}.to_json if request.user_agent !~ Regexp.new(config.user_agnet_pattern)
end

# Movie live cast
get '/' do
  movies = []
  cd config.public_folder do
    movies = Dir["**/*"].select { |f| ['mp4', 'm4v', 'mov'].include?(f.split('.').last.downcase) and !File.directory?(f) }.sort.to_json
  end
  movies
end

get "/info/:file" do
  f = params[:file]
  if f =~ /%252F/  # Linux server
    f.gsub!('%252F', '/')
  else             # OS X server
    f.gsub!('%2F', '/')
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

get '/db_search' do
  keyword = params[:keyword]
  return db_search(keyword)
end

delete "/remove/:file" do
  f = params[:file]
  if f =~ /%252F/  # Linux server
    f.gsub!('%252F', '/')
  else             # OS X server
    f.gsub!('%2F', '/')
  end
  cd config.public_folder do
    if File.exists?(f)
      rm_f (is_windows ? f : f.shellescape)
    end
  end
  {status: 'done'}.to_json
end

# Torrents related
get '/torrents' do
  include_stats = params[:stats]
  datelist = []
  items_counts = []
  folders = config.relative_folders
  cd config.public_folder do

    if File.exists?(folders[0])
      cd folders[0] do
        list = Dir["**"].select{ |f| !(['SyncArchive', 'tu.rb', 'Icon?'].include?(f) or f =~ /Icon/) }.sort_by { |x|
          m = x[1...x.index(']')].split('-')
          [m.length, *m.map{|a|a.to_i}]
        }.reverse

        if include_stats
          items_counts += list.map do |d|
            c = 0
            cd d do
              c = Dir["*"].select do |f|
                ["jpg", "gif", "png", "bmp", "jpeg"].index(f.split(".").last.downcase)
              end.count
            end
            c
          end
        end
        datelist += list
      end
    end
  end
  return include_stats ? {"items" => datelist, "count" =>  items_counts}.to_json : datelist.to_json
end

get "/torrent/:hash" do
  cache_dir = config.torrent_cache
  cfdl_cmd = config.cfdl_cmd
  info_hash = params[:hash]
  target_file = File.join(cache_dir, "#{info_hash}.torrent")
  if File.exists?(target_file)
    content_type 'application/octet-stream'
    send_file target_file
  else
    system("#{cfdl_cmd} -d wget -u https://itorrents.org/torrent/#{info_hash}.torrent -- -O #{target_file}")
    if File.exists?(target_file)
      content_type 'application/octet-stream'
      send_file target_file
    else
      status 404
    end
  end
end

get %r{/search/(.+)} do
  keyword = URI.unescape params[:captures].first
  folder = config.relative_folders.first
  cd config.public_folder do
    cd File.join(folder, keyword) do
      return Dir["*"].select do |f|
        ["jpg", "gif", "png", "bmp", "jpeg"].index(f.split(".").last.downcase)
      end.sort_by do |a|
        c = a.split('_')
        [c.first, c.last.to_i]
      end.map{ |f| File.join(folder, keyword, f) }.to_json
    end
  end
end

get "/hash/:file" do
  fileParam = params[:file]
  if (fileParam.downcase.include? '%2f' or fileParam.downcase.include? '%252f') and fileParam.downcase.include? 'bt'
    f = slash_process(params[:file])
  else
    f = Base64.decode64 params[:file]
  end
  cd config.public_folder do
    tr = torrent_with_pic f
    meta = BEncode.load_file(tr)
    info_hash = Digest::SHA1.hexdigest(meta["info"].bencode)
    return {hash: info_hash, file: URI::encode(tr)}.to_json
  end
end

get "/torrent/:hash" do
  cache_dir = config.torrent_cache
  cfdl_cmd = config.cfdl_cmd
  target_file = File.join(cache_dir, "#{hash}.torrent")
  if File.exists?(target_file)
    send_file target_file
    return
  end
  cd cache_dir do
    system("#{cfdl_cmd} -d curl -u http://itorrents.org/torrent/#{hash}.torrent> /dev/null 2>&1")
  end
  if File.exists?(target_file)
    if File.stat(target_file).size < 512 # Soft limit
      rm_f(target_file)
      status 404
    else
      send_file target_file
    end
  else
    status 404
  end
end

get '/kitty/:keyword/?:page?/?' do
  keyword = params['keyword']
  page = params['page'] || 1
  target_file = "/tmp/#{keyword}.html"
  cfdl_cmd = config.cfdl_cmd
  system("#{cfdl_cmd} -d wget -u https://www.torrentkitty.tv/search/#{URI::encode(keyword)}/#{page} -- -O #{target_file}")
  if File.exists?(target_file)
    content_type "text/html"
    return open(target_file).read
  else
    status 404
  end
end
