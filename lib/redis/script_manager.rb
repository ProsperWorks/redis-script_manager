require "redis/script_manager/version"

class Redis
  class ScriptManager

    # TODO: rubocop

    # TODO: rdoc

    # Efficiently evaluates a Lua script on Redis.
    #
    # Makes a best effort to moderate bandwidth by leveraging EVALSHA
    # and managing the SCRIPT LOAD state.
    #
    # @param redis a Redis to call, must respond to :eval, :evalsha,
    # and :script
    #
    # @param lua a String, the Lua script to execute on redis
    #
    # @param keys a list of String, the keys which will bind to the KEYS
    # list in the lua script.
    #
    # @param args a list of arguments which will bind to ARGV list in
    # the lua script.
    #
    # @return the return result of evaluating lua against keys and args
    # on redis
    #
    # TODO: Should this just monkey-patch over Redis.eval?
    #
    def self.eval_gently(redis,lua,keys=[],args=[])
      [:eval,:evalsha,:script,:client].each do |method|
        if !redis.respond_to?(method) || !redis.respond_to?(:script)
          raise ArgumentError, "bogus redis #{redis}, no #{method}"
        end
      end
      if !lua.is_a?(String)
        raise ArgumentError, "bogus lua #{lua}"
      end
      if !keys.is_a?(Array)
        raise ArgumentError, "bogus keys #{keys}: non-array"
      end
      keys_classes = keys.map(&:class).uniq
      if [] != keys_classes - [String,Symbol]
        raise ArgumentError, "bogus keys #{keys}: bad types in #{keys_classes}"
      end
      if !args.is_a?(Array)
        raise ArgumentError, "bogus args #{args}"
      end
      if keys.size < 1
        raise ArgumentError, 'Twemproxy intolerant of 0 keys in EVAL or EVALSHA'
      end
      #
      # Per http://redis.io/commands/eval:
      #
      #   Redis does not need to recompile the script every time as it
      #   uses an internal caching mechanism, however paying the cost of
      #   the additional bandwidth may not be optimal in many contexts."
      #
      # So, where the bandwidth imposed by uploading a short script is
      # small, we will just use EVAL.  Also, in MONITOR streams it can
      # be nice to see the Lua instead of a bunch of noisy shas.
      #
      # However, where the script is long we try to conserve bandwidth
      # by trying EVALSHA first.  In case our script has never been
      # uploaded before, or if the Redis suffered a FLUSHDB or SCRIPT
      # FLUSH, we catch NOSCRIPT error, recover with SCRIPT LOAD, and
      # repeat the EVALSHA.
      #
      # Caveat: if all of this is wrapped in a Redis pipeline, then the
      # first EVALSHA returns a Redis::Future, not a result.  We won't
      # know whether it throws an error until after the pipeline - and
      # after we've committed to the rest of our stream of commands.
      # Thus, we can't recover from a NOSCRIPT error.
      #
      # To be safe in this pipelined-but-not-in-script-database edge
      # case, we stick with simple EVAL when we detect we are running
      # within a pipeline.
      #
      if configuration.do_minify_lua
        lua = self.minify_lua(lua)
      end
      if lua.size < configuration.max_tiny_lua
        _statsd_increment("eval")
        return redis.eval(lua,keys,args)
      end
      if configuration.do_preload
        #
        # I tested RLEC in ali-staging with this script:
        #
        #   sha = Redis.current.script(:load,'return redis.call("get",KEYS[1])')
        #   100.times.map { |n| "foo-#{n}" }.each do |key|
        #     set = Redis.current.set(key,key)
        #     get = Redis.current.evalsha(sha,[key])
        #     puts "%7s %7s %7s" % [key,get,set]
        #   end
        #
        # Sure enough, all 100 EVALSHA worked.  Since ali-staging is a
        # full-weight sharded RLEC, this tells me that SCRIPT LOAD
        # propagates to all Redis shards in RLEC.
        #
        # Thus, we can trust that any script need only be sent down a
        # particular Redis connection once.  Thereafter we can assume
        # EVALSHA will work.
        #
        # I do not know if the same thing will happen in Redis Cluster,
        # and I am just about certain that the more primitive
        # Twemproxy-over-array-of-plain-Redis will *not* propagate
        # SCRIPT this way.
        #
        # Here is an twemproxy issue which tracks this question
        # https://github.com/twitter/twemproxy/issues/68.
        #
        # This implementation is meant to transmit each script to each
        # Redis no more than once per process, and thereafter be
        # pure-EVALSHA.
        #
        sha                = Digest::SHA1.hexdigest(lua)
        sha_connection_key = [redis.object_id,sha]
        if !@@preloaded_shas.include?(sha_connection_key)
          _statsd_increment("preloaded_shas.cache_miss")
          new_sha = redis.script(:load,lua)
          if !new_sha.is_a?(Redis::Future)
            if sha != new_sha
              raise RuntimeError, "mismatch #{sha} vs #{new_sha} for lua #{lua}"
            end
          end
          @@preloaded_shas << sha_connection_key
        else
          _statsd_increment("preloaded_shas.cache_hit")
        end
        result   = redis.evalsha(sha,keys,args)
        if configuration.preload_cache_size < @@preloaded_shas.size
          #
          # To defend against unbound cache size, at a predetermined
          # limit throw away half of them.
          #
          # It is benign to re-load a script, just a performance blip.
          #
          # If these caches are running away in size, we have a worse
          # time: redis.info.used_memory_lua could be growing without
          # bound.
          #
          _statsd_increment("preloaded_shas.cache_purge")
          num_to_keep      = @@preloaded_shas.size / 2
          @@preloaded_shas = @@preloaded_shas.to_a.sample(num_to_keep)
        end
        cache_size         = @@preloaded_shas.size
        _statsd_timing("preloaded_shas.cache_size",cache_size)
        return result
      end
      in_pipeline = redis.client.is_a?(Redis::Pipeline) # thanks @marshall
      if in_pipeline
        _statsd_increment("pipeline_eval")
        return redis.eval(lua,keys,args)
      end
      sha = Digest::SHA1.hexdigest(lua)
      begin
        _statsd_increment("evalsha1")
        result = redis.evalsha(sha,keys,args)
        if result.is_a?(Redis::Future)
          #
          # We should have detected this above where we checked whether
          # redis.client was a pipeline.
          #
          raise "internal error: unexpected Redis::Future from evalsha"
        end
        result
      rescue Redis::CommandError => ex
        if nil != ex.to_s.index('NOSCRIPT') # some vulerability to change in msg
          _statsd_increment("script_load")
          new_sha = redis.script(:load,lua)
          if sha != new_sha
            raise RuntimeError, "mismatch #{sha} vs #{new_sha} for lua #{lua}"
          end
          _statsd_increment("evalsha2")
          return redis.evalsha(sha,keys,args)
        end
        raise ex
      end
    end

    @@preloaded_shas = Set[] # [redis.object_id,sha(lua)] which have been loaded

    def self.purge_preloaded_shas # for test, clean state
      @@preloaded_shas = Set[]
    end

    # To save bandwidth, minify the Lua code.
    #
    def self.minify_lua(lua)
      lua
        .split("\n")
        .map    { |l| l.gsub(/\s*--[^'"]*$/,'').strip } # rest-of-line comments
        .reject { |l| /^\s*$/ =~ l }                    # blank lines
        .join("\n")
    end

    # Reports a single count on the requested metric to statsd (if
    # any).
    #
    # @param metric String
    #
    def self._statsd_increment(metric)
      if configuration.statsd
        configuration.statsd.increment(configuration.stats_prefix+metric)
      end
    end

    # Reports a timing on the requested metric to statsd (if any).
    #
    # @param metric String
    #
    def self._statsd_timing(metric,timing)
      if configuration.statsd
        configuration.statsd.timing(configuration.stats_prefix+metric,timing)
      end
    end

    # @returns the current Redis::ScriptManager::Configuration.
    #
    def self.configuration
      @configuration ||= Configuration.new
    end

    # Sets the current Redis::ScriptManager::Configuration.
    #
    def self.configuration=(configuration)
      @configuration = configuration
    end

    # Yields the current Redis::ScriptManager::Configuration, supports
    # the typical gem configuration pattern:
    #
    #   Redis::ScriptManager.configure do |config|
    #     config.statsd             = $statsd
    #     config.stats_prefix       = 'foo'
    #     config.minify_lua         = true
    #     config.max_tiny_lua       = 1235
    #     config.preload_shas       = true
    #     config.preload_cache_size = 10
    #   end
    #
    def self.configure
      yield configuration
    end

    class Configuration

      # Defaults to nil. If non-nil, lots of stats will be tracked via
      # statsd.increment and statsd.timing.
      #
      def statsd
        @statsd || nil
      end
      def statsd=(statsd)
        if statsd && !statsd.respond_to?(:increment)
          raise ArgumentError, "bogus statsd A #{statsd}"
        end
        if statsd && !statsd.respond_to?(:timing)
          raise ArgumentError, "bogus statsd B #{statsd}"
        end
        @statsd = statsd
      end

      # Defaults to ''.
      #
      # Prefixed onto all metrics.
      #
      def stats_prefix
        @stats_prefix || ''
      end
      def stats_prefix=(stats_prefix)
        if stats_prefix && !stats_prefix.is_a?(String)
          raise ArgumentError, "bogus stats_prefix"
        end
        @stats_prefix = stats_prefix || ''
      end

      # Defaults to false.
      #
      # If true, all Lua is minified conservatively to save bandwidth
      # before any other logic or evaluation.
      #
      def do_minify_lua
        @do_minify_lua || false
      end
      def do_minify_lua=(do_minify_lua)
        @do_minify_lua = [true,'true'].include?(do_minify_lua)
      end

      # Scripts shorter than max_tiny_lua are always EVALed.
      #
      # We skip all logic regarding EVALSHA, extra round-trips for
      # SCRIPT LOAD, etc.
      #
      # Defaults to 512.  Integers and Strings which convert to Integers OK.
      #
      def max_tiny_lua
        @max_tiny_lua || 512
      end
      def max_tiny_lua=(max_tiny_lua)
        @max_tiny_lua = max_tiny_lua.to_i
      end

      # Defaults to false.
      #
      # If true, shas are preloaded for each Redis connection (which
      # make safe to use EVALSHA even in pipelines).
      #
      def do_preload
        @do_preload || false
      end
      def do_preload=(do_preload)
        @do_preload = [true,'true'].include?(do_preload)
      end

      # The cache of shas which have been preloaded is not allowed to
      # grow larger than this value.
      #
      # Defaults to 1000.
      #
      def preload_cache_size
        @preload_cache_size || 1000
      end
      def preload_cache_size=(preload_cache_size)
        @preload_cache_size = preload_cache_size.to_i
      end

    end

  end

end
