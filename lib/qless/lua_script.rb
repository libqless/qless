require 'digest/sha1'
require 'qless_lua'

module Qless
  LuaScriptError = Class.new(Qless::Error)

  # Wraps a lua script. Knows how to reload it if necessary
  class LuaScript
    attr_reader :sha, :name, :redis

    def initialize(name, redis)
      @name  = name
      @redis = redis
      @sha = Digest::SHA1.hexdigest(script_contents)
    end

    def script_contents
      @script_contents ||= QlessLua::QLESS_SOURCE
    end

    def reload
      @sha = @redis.script(:load, script_contents)
    end

    def call(*argv)
      handle_no_script_error do
        _call(*argv)
      end
    rescue Redis::CommandError => e
      match = e.message.match('user_script:\d+:\s*(\w+.+$)')
      raise LuaScriptError.new(match[1]) if match
      raise e
    end

    private

    if USING_LEGACY_REDIS_VERSION
      def _call(*argv)
        @redis.evalsha(@sha, 0, *argv)
      end
    else
      def _call(*argv)
        @redis.evalsha(@sha, keys: [], argv: argv)
      end
    end

    def handle_no_script_error
      yield
    rescue ScriptNotLoadedRedisCommandError
      reload
      yield
    end

    # Module for notifying when a script hasn't yet been loaded
    module ScriptNotLoadedRedisCommandError
      MESSAGE_RE = /^NOSCRIPT No matching script/

      def self.===(error)
        error.is_a?(Redis::CommandError) && MESSAGE_RE.match?(error.message)
      end
    end
  end

  # Provides a simple way to load and use lua-based Qless plugins.
  # This combines the qless-lib.lua script plus your custom script
  # contents all into one script, so that your script can use
  # Qless's lua API.
  class LuaPlugin < LuaScript
    COMMENT_LINES_RE = /^\s*--.*$\n?/
    QLESS_LIB_CONTENTS = QlessLua::QLESS_LIB_SOURCE.gsub(COMMENT_LINES_RE, '')

    def initialize(name, redis, plugin_contents)
      @plugin_contents = plugin_contents.gsub(COMMENT_LINES_RE, '')
      super(name, redis)
    end

    private

    def script_contents
      @script_contents ||= [QLESS_LIB_CONTENTS, @plugin_contents].join("\n\n")
    end
  end
end
