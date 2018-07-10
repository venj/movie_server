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

include FileUtils

class AppConfig
  def initialize
    @vars = YAML.load(open(File.join(File.dirname(__FILE__), 'server_conf.yml')).read)
  end

  def public_folder
    @vars['public_folder']
  end

  def lx_command
    @vars['lixian_command']
  end

  def lx_hash_command
    @vars['lixian_hash_command']
  end

  def max_pic_size
    @vars['max_pic_size'].to_i * 1024
  end

  def relative_folders
    @vars['relative_folders']
  end

  def default_sort?
    @vars['default_sort_order']
  end

  def basic_auth_enabled?
    @vars['enable_basic_auth']
  end

  def username
    @vars['auth'][0]
  end

  def password
    @vars['auth'][1]
  end

  def tr_db_path
    @vars['tr_db_path']
  end

  def ssl_enabled
    @vars['ssl_enabled']
  end

  def ssl_key_path
    @vars['ssl_key_path']
  end

  def ssl_cert_path
    @vars['ssl_cert_path']
  end

  def user_agnet_pattern
    @vars['user_agnet_pattern']
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
      if is_windows
        return tr_name
      else
        return tr_name.shellescape
      end
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
  protected! if config.basic_auth_enabled?
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
  target_file = File.join(cache_dir, "#{hash}.torrent")
  system("#{cfdl_cmd} -d wget -u http://itorrents.org/torrent/#{hash}.torrent -- -O #{target_file}")
  if File.exists?(target_file)
    send_file target_file
  else
    status 404
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
  lx_command = config.lx_command
  lx_hash_command = config.lx_hash_command
  cd config.public_folder do
    result = %x|#{lx_hash_command} #{torrent_with_pic f}|.split(' ')[0]
    return {hash: result.strip}.to_json
  end
end

get "/torrent/:hash" do
  cache_dir = config.torrent_cache
  cfdl_cmd = config.cfdl_cmd
  target_file = File.join(cache_dir, "#{hash}.torrent")
  system("#{cfdl_cmd} -d wget -u http://itorrents.org/torrent/#{hash}.torrent -- -O #{target_file}")
  if File.exists?(target_file)
    send_file target_file
  else
    status 404
  end
end

get "/lx/:file/:async" do
  f = slash_process(params[:file])
  lx_command = config.lx_command
  cd config.public_folder do
    if params[:async] == '1'
      fork {
        exec "#{lx_command} add #{torrent_with_pic f}"
      }
      return {status: 'done'}.to_json
    elsif params[:async] == "0"
      result = %x[#{lx_command} add #{torrent_with_pic f}]
      if result =~ /completed/
        status = 'completed'
      elsif result =~ /waiting/
        status = 'waiting'
      elsif result =~ /downloading/
        status = 'downloading'
      elsif result =~ /\[0976\]/
        status = 'Oh no, 0976'
      elsif result =~ /Verification code required/
        status = 'Oh no, code'
      else
        status = 'failed or unknown'
      end
      return {status: status}.to_json
    end
  end
end