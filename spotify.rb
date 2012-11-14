require 'rubygems'
require 'thread'
require 'hallon'
require 'hallon-openal'

module FloydCast
  class API
    def initialize(options)
      @username = options["username"]
      @password = options["password"]
      @semaphore = Mutex.new
      @queue = Queue.new
      init_player_thread
    end

    def search(query)
      search = Hallon::Search.new(query)
      search.load
      return nil if search.tracks.size.zero?

      search.tracks[0]
    end

    def play(track)
      @semaphore.synchronize do
        puts "pushing to queue #{track.name}"
        @queue.push(track)
      end
    end

    def pause
      player.pause
    end

    def stop
      player.stop
    end

    def login!
      session = Hallon::Session.initialize IO.read('./spotify_appkey.key')
      session.login!(@username, @password)
    end

    private

    def player
      @player ||= Hallon::Player.new(Hallon::OpenAL)
    end

    def init_player_thread
      Thread.new do
        while true do
          track = nil
          @semaphore.synchronize do
            unless @queue.empty?
              track = @queue.pop
            end
          end
          if track
            puts "playing track #{track.name}"
            player.play!(track)
          end

          sleep(1)
        end
      end
    end

  end
end