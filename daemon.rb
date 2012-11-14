#!/usr/bin/ruby
# ---------------------------------------------------------------------
# MODULES
# ---------------------------------------------------------------------
require 'rubygems'
require 'daemonize'
require 'json'
require "yaml"
require 'pusher-client'
require 'ruby-debug'
require './spotify'
include Daemonize
include Process
# ---------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------
$daemon = {
  :name => "Test Daemon",                  # daemon name
  :abbr => "testd",                        # daemon abbreviation
  :author => "(c) 2008 author",            # daemon author
  :version => "0.1",                       # actual version
  :file_log => "./daemon.log",  # log path
  :file_pid => "./daemon.pid",  # process id path
  :delay_sleep => 1,                       # seconds
  :user => 'tux',                          # working data user
  :grp => 'tux',                           # working data group
  :background => false,                    # background mode
  :work => true                            # daemon work flag
}

$daemon_log = nil
$daemon_pid = nil
# ---------------------------------------------------------------------

def daemon_log(str)
  puts "[#{Time.now.strftime("%m/%d/%Y-%H:%M:%S")}] #{str}"
end

def daemon_terminate
  $daemon[:work] = false
end

def daemon_stop
  daemon_log("Stopping working process...")
  $daemon_pid.close
  File.delete($daemon[:file_pid])
end

def daemon_start
  if File.exist?($daemon[:file_pid]) then
    daemon_log("Process already running. If it`s not - remove the pid file")
    exit
  end

  daemon_log("Starting process...")
  daemonize if $daemon[:background]

  begin
    $daemon_pid = File.new($daemon[:file_pid],"w")
  rescue Errno::EACCES
    daemon_log("Cannot create PID file. Check the permissions and try again!")
    $daemon_pid = nil
    exit
  end

  daemon_work
end

def daemon_work
  if $daemon_pid
    $daemon_pid.sync = true
    $daemon_pid.puts(Process.pid.to_s)

    init_spotify
    init_pusher

    begin
      while $daemon[:work] do
        daemon_handle_signals
        sleep($daemon[:delay_sleep])
      end
    rescue Exception => e
      daemon_log("Error: #{e.message}")
    end

    daemon_stop
  end
end

def daemon_handle_signals
  # termination signal
  Signal.trap("TERM") do
    daemon_log("TERM signal received.")
    daemon_terminate
  end

  # kill signal
  Signal.trap("KILL") do
    daemon_log("KILL signal received.")
    daemon_terminate
  end

  # keyboard interruption
  Signal.trap("INT") do
    daemon_log("SIGINT signal received.")
    daemon_terminate
  end

  Signal.trap("TSTP") do
    daemon_log("SIGTSTP signal received.")
  end
end

def daemon_show_version
  puts "#{$daemon[:name]} v#{$daemon[:version]} #{$daemon[:author]}"
end

def daemon_show_usage
  daemon_show_version
  puts "Usage:"
  puts "    -b, --background        work in background mode"
  puts "    -v, --version           view version of daemon"
  puts "    -h, --help              view this help"
end

def daemon_parse_opts
  return true if ARGV.length == 0

  case ARGV[0]
    when '-b', '--background'
      $daemon[:background] = true;
      return true

    when '-v', '--version'
      daemon_show_version

    when '-h', '--help'
      daemon_show_usage
    else
      puts "Invalid argument: #{ARGV[0]}" if !ARGV[0].nil?
      daemon_show_usage
  end

  false
end

def daemon_main
  daemon_start if daemon_parse_opts
end

def init_spotify
  spotify_config = YAML::load_file('./spotify.yml')
  $api = FloydCast::API.new(spotify_config)
  $api.login!
end

def init_pusher
  PusherClient.logger = Logger.new(STDOUT)
  pusher_config = YAML::load_file('./pusher.yml')
  socket = PusherClient::Socket.new(pusher_config["key"], {:secret => pusher_config["secret"]})
  socket.connect(true)
  socket.subscribe('floydcast')
  socket['floydcast'].bind('queue-song') do |data|
    data = JSON.parse(data)
    requested_track = $api.search(data["query"])
    $api.play(requested_track)
  end
  socket['floydcast'].bind('skip-song') do |data|
    $api.skip
  end
end

daemon_main