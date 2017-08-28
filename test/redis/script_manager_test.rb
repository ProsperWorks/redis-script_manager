require 'test_helper'

class Redis::ScriptManagerTest < Minitest::Test

  # When ENV['REDIS_URL'] is set, we run a greatly expanded test suite
  # which actually talk to Redis.
  #
  # When ENV['REDIS_URL'] is unset, only a smaller set run.
  #
  def self.redis
    ENV['REDIS_URL'] ? (@@redis ||= Redis.new(:url => ENV['REDIS_URL'])) : nil
  end
  def redis
    self.class.redis
  end

  # Make sure each test starts with a fresh default configuration.
  #
  def setup
    Redis::ScriptManager.configuration = Redis::ScriptManager::Configuration.new
    Redis::ScriptManager.purge_preloaded_shas
  end
  def teardown
    Redis::ScriptManager.configuration = Redis::ScriptManager::Configuration.new
  end

  # Make sure :configuration and :configration= fit together in the
  # standard pattern.
  #
  def test_configuration
    config1 = Redis::ScriptManager.configuration
    config2 = Redis::ScriptManager::Configuration.new
    refute_nil   config1
    refute_equal config2.object_id, config1.object_id
    Redis::ScriptManager.configuration = config2
    config3 = Redis::ScriptManager.configuration
    assert_equal config2.object_id, config3.object_id
  end

  # Make sure :configure fits together in the standard pattern.
  #
  def test_configure
    Redis::ScriptManager.configuration.max_tiny_lua = 100
    assert_equal   100, Redis::ScriptManager.configuration.max_tiny_lua
    Redis::ScriptManager.configuration.max_tiny_lua = 113
    assert_equal   113, Redis::ScriptManager.configuration.max_tiny_lua
    Redis::ScriptManager.configure do |config|
      assert_equal 113, config.max_tiny_lua
      config.max_tiny_lua = 213
    end
    assert_equal   213, Redis::ScriptManager.configuration.max_tiny_lua
  end

  # Make sure the defaults and assignability for each configuration
  # parameter are as expected.
  #
  def test_configuration_defaults_and_assignment
    config = Redis::ScriptManager::Configuration.new
    #
    # statsd defaults to nil
    #
    assert_nil   config.statsd
    #
    # stats_prefix defaults to '' and accepts strings.
    #
    assert_equal '', config.stats_prefix
    config.stats_prefix  = 'a'       ; assert_equal 'a',   config.stats_prefix
    config.stats_prefix  = 'foo'     ; assert_equal 'foo', config.stats_prefix
    config.stats_prefix  = nil       ; assert_equal '',    config.stats_prefix
    #
    # do_minify_lua defaults to false and accepts booleans or
    # bool-like strings.
    #
    assert_equal false, config.do_minify_lua
    config.do_minify_lua = true      ; assert_equal true,  config.do_minify_lua
    config.do_minify_lua = false     ; assert_equal false, config.do_minify_lua
    config.do_minify_lua = 'true'    ; assert_equal true,  config.do_minify_lua
    config.do_minify_lua = 'false'   ; assert_equal false, config.do_minify_lua
    #
    # max_tiny_lua defaults to 512 and accepts integers or
    # int-like strings.
    #
    assert_equal 512, config.max_tiny_lua
    config.max_tiny_lua = 13         ; assert_equal 13,    config.max_tiny_lua
    config.max_tiny_lua = '123'      ; assert_equal 123,   config.max_tiny_lua
    #
    # do_preload defaults to false and accepts booleans or bool-like
    # strings.
    #
    assert_equal false, config.do_preload
    config.do_preload = true         ; assert_equal true,  config.do_preload
    config.do_preload = false        ; assert_equal false, config.do_preload
    config.do_preload = 'true'       ; assert_equal true,  config.do_preload
    config.do_preload = 'false'      ; assert_equal false, config.do_preload
    #
    # preload_cache_size defaults to 1000 and accepts integers or
    # int-like strings.
    #
    assert_equal 1000, config.preload_cache_size
    config.preload_cache_size = 11  ; assert_equal 11, config.preload_cache_size
    config.preload_cache_size = '7' ; assert_equal 7,  config.preload_cache_size
  end

  # Confirm that minify_lua does not crash and has expected results.
  #
  # We are not smart enough to confirm that minify_lua preserves
  # meaning (cf. https://en.wikipedia.org/wiki/Halting_problem), only
  # that it runs cleanly.
  #
  def test_minify_lua
    #
    # Make sure we cut blank lines and "--"-to-end-of-line comments.
    #
    raw = "\n" +
          "--  \n" +
          "  \n         " +
          "-- Lorem ipsum                    \n" +
          "--\n" +
          "local ick_key        = KEYS[1] -- lorem                        \n" +
          "local ick_ver        = redis.call('GET',ick_key)  --    ipsum\n"
    min = "local ick_key        = KEYS[1]\n" +
          "local ick_ver        = redis.call('GET',ick_key)"
    assert_equal min, Redis::ScriptManager.minify_lua(raw)
    #
    # Make sure the regexp do not stomp on quoted "--".
    #
    raw = "return 'be careful -- do not delete this' --  but this can go   \n" +
          "return \"ditto -- preserve this piece\" --  but please cut this \n"
    min = "return 'be careful -- do not delete this'\n" +
          "return \"ditto -- preserve this piece\""
    assert_equal min, Redis::ScriptManager.minify_lua(raw)
    #
    # Clean up a real snippet of LUA_ICKCOMMIT, check that we gobble indents.
    #
    # "too many results to unpack" is not minified to nothingness
    # because of the defenisveness of the regex which detects
    # "--"-to-end-of-line comments.
    #
    raw = "if true then\n" +
          "  --\n" +
          "  -- This avoids the \"too many results to unpack\" problem, but\n" +
          "  -- it smells regrettably heavyweight.\n" +
          "  --\n  " +
          "  -- Unfortunately, Lua does not seem to offer the kind of\n" +
          "  -- each_slice() functionality to which I have become\n" +
          "  -- accustomed.\n" +
          "  --\n" +
          "  -- Consider whether crossing into redis.call() O(N) times is\n" +
          "  -- expensive enough to avoid it by breaking ARGV into\n" +
          "  -- something which can still pass unpack(), but larger\n" +
          "  -- than 1 at a time.\n" +
          "  --\n" +
          "  local num_removed = 0\n" +
          "  for i,v in ipairs(ARGV) do\n" +
          "    num_removed = num_removed + redis.call('ZREM',ick_cset_key,v)\n" +
          "  end\n" +
          "  return num_removed\n" +
          "else\n" +
          "  --\n" +
          "  -- This produces the \"too many results to unpack\" w/ big ARGV\n" +
          "  --\n" +
          "  return redis.call('ZREM',ick_cset_key,unpack(ARGV))\n" +
          "end\n"
    min = "if true then\n" +
          "-- This avoids the \"too many results to unpack\" problem, but\n" +
          "local num_removed = 0\n" +
          "for i,v in ipairs(ARGV) do\n" +
          "num_removed = num_removed + redis.call('ZREM',ick_cset_key,v)\n" +
          "end\n" +
          "return num_removed\n" +
          "else\n" +
          "-- This produces the \"too many results to unpack\" w/ big ARGV\n" +
          "return redis.call('ZREM',ick_cset_key,unpack(ARGV))\n" +
          "end"
    assert_equal min, Redis::ScriptManager.minify_lua(raw)
  end

  # A mock of the limited aspects of the statsd-ruby gem interface
  # which are important to redis-script_manager.
  #
  class MockStatsd
    def increment(metric)
      @log ||= []
      @log << [:increment, metric]
    end
    def timing(metric,timing)
      @log ||= []
      @log << [:timing, metric, timing]
    end
    def flush
      log = @log
      @log = nil
      log
    end
  end

  # Test the effects of statsd and stats_prefix configurations.
  #
  def test_stats
    #
    # The statsd wrappers do not crash when there is no statsd.
    #
    Redis::ScriptManager.configuration.statsd       = nil
    Redis::ScriptManager.configuration.stats_prefix = nil
    Redis::ScriptManager._statsd_increment('foo')
    Redis::ScriptManager._statsd_timing('foo',123)
    #
    # The statsd wrappers log when there is a statsd.
    #
    Redis::ScriptManager.configuration.statsd       = MockStatsd.new
    Redis::ScriptManager.configuration.stats_prefix = nil
    Redis::ScriptManager._statsd_increment('foo')
    Redis::ScriptManager._statsd_timing('bar',123)
    expected = [
      [ :increment, 'foo'         ],
      [ :timing,    'bar',    123 ],
    ]
    assert_equal expected, Redis::ScriptManager.configuration.statsd.flush
    #
    # The statsd wrappers incorporate the stats_prefix.
    #
    Redis::ScriptManager.configuration.statsd       = MockStatsd.new
    Redis::ScriptManager.configuration.stats_prefix = 'x,'
    Redis::ScriptManager._statsd_increment('baz')
    Redis::ScriptManager._statsd_timing('bang',321)
    expected = [
      [ :increment, 'x,baz'       ],
      [ :timing,    'x,bang', 321 ],
    ]
    assert_equal expected, Redis::ScriptManager.configuration.statsd.flush
  end

  [
    #
    # In redis-namespace 1.5.3 they deprecated support for certain
    # Redis commands, including SCRIPT, with messaging:
    #
    #   Passing 'script' command to redis as is; administrative
    #   commands cannot be effectively namespaced and should be called
    #   on the redis connection directly; passthrough has been
    #   deprecated and will be removed in redis-namespace 2.0 ...
    #
    # So this test takes 2 redis connectors, one which is used for
    # SCRIPT and one which is used for everything else.
    #
    [ 'regular',   redis                                    ],
    [ 'namespace', Redis::Namespace.new('foo',redis: redis) ],
  ].each do |test_name,redis_to_test|
    define_method("test_sanity_EVAL_EVALSHA_and_SCRIPT_LOAD_for_#{test_name}") do
      next if !redis
      #
      # Clean slate:
      #
      # We use redis for this, not redis_to_test, because
      # Redis::Namespace 1.5.3 dropepd support for SCRIPT.
      #
      redis.script(:flush) # use redis, not redis_to_test
      #
      # We can EVAL a simple inline Lua snippet:
      #
      # Note that EVAL must have at least 1 key, or Twemproxy will
      # reject it and Ruby will interpret that as a
      # Redis::ConnectionError.
      #
      # In contrast, on a naked non-Clustered Redis or a RedisLabs
      # Enterprise Cluster link, EVAL-with-no-keys is OK.
      #
      # https://github.com/twitter/twemproxy/blob/master/notes/redis.md
      # says that:
      #
      #   EVAL and EVALSHA support is limited to scripts that take at
      #   least 1 key. ... If multiple keys are used, all keys must
      #   hash to the same server. If you use more than 1 key, the
      #   proxy does no checking to verify that all keys hash to the
      #   same server, and the entire command is forwarded to the
      #   server that the first key hashes to.
      #
      # Which is kind of odd, but ok.  Min 1 key is enforced, as is
      # agreement among multiple keys.
      #
      got = redis_to_test.eval('return KEYS',['{k}1','{k}2'],[1,2])
      assert got == ['{k}1','{k}2'] || got == ['foo:{k}1','foo:{k}2']
      #
      assert_equal 123, redis_to_test.eval('return 123',['k'])           # 1 key
      assert_equal 123, redis_to_test.eval('return 123',['a{k}','b{k}']) # 1 slot
      #
      # We can pass args to a simple inline Lua snippet, results are stringy.
      #
      assert_equal ['1','2'], redis_to_test.eval('return ARGV',['k','k'],[1,2])
      #
      # We can inspect keys from a simple inline Lua snippet.
      #
      got = redis_to_test.eval('return KEYS',['k1','k2'],[1,2])
      case test_name
      when 'regular'
        assert_equal ['k1','k2'],         got
      when 'namespace'
        #
        # We notice different results from Lua 'return KEYS' when redis
        # is namespaced.
        #
        # This is good - it means the eval function is expanding the
        # keys as expected, to include the namespace, before they are
        # getting passed to the Lua invocation on Redis (probably even
        # before they even get passed over the connection to Redis).
        #
        assert_equal ['foo:k1','foo:k2'], got
      end
      #
      # The empty script is legit, and slightly surprisingly returns nil.
      #
      assert_nil redis_to_test.eval('',['k'])
      #
      # We can SCRIPT LOAD a Lua script into Redis and get a SHA.
      #
      # The SHAs are very stable, being defined in
      # http://redis.io/commands/script-load to be the "the SHA1
      # digest of the script added into the script cache", with SHA1
      # being a very clear standard.
      #
      sha1 = redis.script(:load,'return 321')
      sha2 = redis.script(:load,"-- comment\nreturn 321")
      sha3 = redis.script(:load,'return ARGV')
      sha4 = redis.script(:load,' return ARGV ')         # stripped?
      assert_equal '9be5674e99667c4b262381e96a4fe5ae976dec6a', sha1
      assert_equal 'a5c990affcb0aa248249b8d6c406cb592c99b9ca', sha2
      assert_equal '4cf2342858f27cba86b2b790280b0ba54885a7d0', sha3
      assert_equal 'fa47ed36f4e66bc6d7ef368bf077e201c6507752', sha4 # no strip
      #
      # We can invoke the scripts via SHA.
      #
      assert_equal       321, redis_to_test.evalsha(sha1,['k'])
      assert_equal       321, redis_to_test.evalsha(sha2,['k'])
      assert_equal ['1','2'], redis_to_test.evalsha(sha3,['k1','k2'],[1,2])
      assert_equal ['4','5'], redis_to_test.evalsha(sha3,['k1','k2'],[4,5])
      #
      # These SHAs match those we can produce internally.  We can
      # exploit this property at runtime to greedily skip the STORE
      # LOAD except when minimally necessary.
      #
      assert_equal Digest::SHA1.hexdigest('return 321'),             sha1
      assert_equal Digest::SHA1.hexdigest("-- comment\nreturn 321"), sha2
      assert_equal Digest::SHA1.hexdigest('return ARGV'),            sha3
      #
      # The behavior when a SHA is unknown to the Redis server is
      # predictable:
      #
      assert_raises(Redis::CommandError) do
        redis_to_test.evalsha('totally-unknown-sha',['k'])
      end
      #
      # ...but similar to the Redis::CommandError we get when we eval
      # bogus scripts:
      #
      assert_raises(Redis::CommandError) do
        redis_to_test.eval('rexxyv',['k'])
      end
      #
      # We can distinguish, somewhat hackily, by checking the body of
      # the message.
      #
      begin
        redis_to_test.evalsha('totally-unknown-sha',['k'])     # bad SHA
        flunk 'should not get here'
      rescue Redis::CommandError => e
        refute_nil e.to_s.index('NOSCRIPT') # ...reports NOSCRIPT
      end
      begin
        redis_to_test.eval('rexxyv',['k'])                     # bogus Lua
        flunk 'should not get here'
      rescue Redis::CommandError => e
        assert_nil e.to_s.index('NOSCRIPT')     # ...has other messaging
      end
    end
  end

  [
    false,
    true,
  ].each do |do_preload|
    define_method("test_eval_lua_in_redis_do_preload_#{do_preload}") do
      next if !redis
      redis.script(:flush)
      Redis::ScriptManager.configuration.do_preload = do_preload
      Redis::ScriptManager.configuration.statsd     = MockStatsd.new
      #
      # Clean slate:
      #
      big_comment = "x" * Redis::ScriptManager.configuration.max_tiny_lua
      #
      # Legit scripts:
      #
      [
        [
          [redis,'',['k']],
          nil,
          [[:increment, "eval"]]
        ],
        [
          [redis,'return 123',['k']],
          123,
          [[:increment, "eval"]]
        ],
        [
          [redis,'return ARGV',['{k}1','{k}2'],[1,2]],
          ['1','2'],
          [[:increment, "eval"]]
        ],
        [
          [redis,'return ARGV[2]',['k'],[1,2,3]],
          '2',                                       # Lua lists are 1-indexed :(
          [[:increment, "eval"]]
        ],
        [
          # long program ends up doing script load
          [redis,"-- #{big_comment}\nreturn 123",['k']],
          123,
          ( do_preload ?
              [
                [:increment, "preloaded_shas.cache_miss"],
                [:timing,    "preloaded_shas.cache_size",1],
              ] :
              [
                [:increment, "evalsha1"],
                [:increment, "script_load"],
                [:increment, "evalsha2"],
              ]
          )
        ],
        [
          # repeated long program skips script, does simple evalsha
          [redis,"-- #{big_comment}\nreturn 123",['k']],
          123,
          ( do_preload ?
              [
                [:increment, "preloaded_shas.cache_hit"    ],
                [:timing,    "preloaded_shas.cache_size", 1],
              ] :
              [
                [:increment, "evalsha1"],
              ]
          )
        ],
      ].each do |args,expect,expect_stats|
        got       = Redis::ScriptManager.eval_gently(*args)
        got_stats = Redis::ScriptManager.configuration.statsd.flush
        assert_equal expect,       got,       args
        assert_equal expect_stats, got_stats, args
      end
      #
      # Bogus args
      #
      [
        [redis,nil],
        [redis,0],
        [nil,'return 123'],
        [redis,'return 123',123],
        [redis,'return 123',[],123],
        [redis,'return 123',[12],123],  # non-string key
        [redis,'return 123',[{}],123],  # non-string key
        [redis,'return 123',[nil],123], # non-string key
        [redis,'return 123',[[]],123],  # non-string key
      ].each do |args|
        assert_raises(ArgumentError) do
          Redis::ScriptManager.eval_gently(*args)
        end
        Redis::ScriptManager.configuration.statsd.flush
      end
      #
      # Since eval_lua_in_redis() uses Redis::CommandError to tell us
      # when to try STORE LOAD, make sure truly bogus scripts can still
      # raise a Redis::CommandError.
      #
      assert_raises(Redis::CommandError) do                                # tiny
        Redis::ScriptManager.eval_gently(redis,'rexxyv',['k'])
      end
      expect_stats = [
        [:increment, "eval"],
      ]
      assert_equal expect_stats, Redis::ScriptManager.configuration.statsd.flush
      #
      # And again with another bogus script over the magic threshold.
      #
      assert_raises(Redis::CommandError) do                                # big
        Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nrexxyv",['k'])
      end
      expect_stats = (
        do_preload ?
          [
            [:increment, "preloaded_shas.cache_miss"],
            # never gets to "preloaded_shas.cache_size"
          ] :
          [
            [:increment, "evalsha1"],
            [:increment, "script_load"],
            # never gets to "evalsha2"
          ]
      )
      assert_equal expect_stats, Redis::ScriptManager.configuration.statsd.flush
    end
  end

  def test_preload_cache_size
    return if !redis
    Redis::ScriptManager.configuration.do_minify_lua      = false
    Redis::ScriptManager.configuration.do_preload         = true
    Redis::ScriptManager.configuration.preload_cache_size = 5
    Redis::ScriptManager.configuration.statsd             = MockStatsd.new
    big_comment                               = "0123456789abcdef" * 32
    Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nreturn 10",['k'])
    Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nreturn 20",['k'])
    Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nreturn 30",['k'])
    Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nreturn 40",['k'])
    Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nreturn 10",['k'])
    Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nreturn 50",['k'])
    Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nreturn 10",['k'])
    Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nreturn 60",['k'])
    Redis::ScriptManager.eval_gently(redis,"-- #{big_comment}\nreturn 70",['k'])
    expect_stats = [
      [:increment, "preloaded_shas.cache_miss"],    # 10
      [:timing,    "preloaded_shas.cache_size", 1],
      [:increment, "preloaded_shas.cache_miss"],    # 20
      [:timing,    "preloaded_shas.cache_size", 2],
      [:increment, "preloaded_shas.cache_miss"],    # 30
      [:timing,    "preloaded_shas.cache_size", 3],
      [:increment, "preloaded_shas.cache_miss"],    # 40
      [:timing,    "preloaded_shas.cache_size", 4],
      [:increment, "preloaded_shas.cache_hit"],     # 10
      [:timing,    "preloaded_shas.cache_size", 4],
      [:increment, "preloaded_shas.cache_miss"],    # 50
      [:timing,    "preloaded_shas.cache_size", 5],
      [:increment, "preloaded_shas.cache_hit"],     # 10
      [:timing,    "preloaded_shas.cache_size", 5],
      [:increment, "preloaded_shas.cache_miss"],    # 60
      [:increment, "preloaded_shas.cache_purge"],
      [:timing,    "preloaded_shas.cache_size", 3],
      [:increment, "preloaded_shas.cache_miss"],    # 70
      [:timing,    "preloaded_shas.cache_size", 4],
    ]
    assert_equal expect_stats, Redis::ScriptManager.configuration.statsd.flush
  end

  def test_implications_of_pipelined
    return if !redis
    Redis::ScriptManager.configuration.do_preload = false
    Redis::ScriptManager.configuration.statsd     = MockStatsd.new
    #
    # Historically, Redis::ScriptManager.eval_gently() could misbehave if
    # called in a pipeline for larger scripts which were not already
    # in the Redis script database.
    #
    # Here, we generated scripts which are certain not to be in that
    # cache, and we try shorter and longer scripts both in and out of
    # pipelines, to check that the bug is fixed.
    #
    # everything works fine without a pipeline
    #
    max_tiny_lua    = Redis::ScriptManager.configuration.max_tiny_lua
    short_str_a     = 'x' * (max_tiny_lua/10)
    long_str_a      = 'x' * max_tiny_lua
    short_lua_a     = "return '#{short_str_a}'" # not cached, will eval
    long_lua_a      = "return '#{long_str_a}'"  # not cached, will evalsha
    short_got_a     = Redis::ScriptManager.eval_gently(redis,short_lua_a,['k'])
    long_got_a      = Redis::ScriptManager.eval_gently(redis,long_lua_a,['k'])
    assert_equal short_str_a, short_got_a
    assert_equal long_str_a,  long_got_a
    #
    # Try the same thing in a pipeline, only the short stuff works.
    #
    short_str_b     = 'y' * (max_tiny_lua/10)
    long_str_b      = 'y' * max_tiny_lua
    short_lua_b     = "return '#{short_str_b}'" # not cached, will eval
    long_lua_b      = "return '#{long_str_b}'"  # not cached, will evalsha
    short_got_b     = nil
    long_got_b      = nil
    redis.pipelined do
      short_got_b   = Redis::ScriptManager.eval_gently(redis,short_lua_b,['k'])
    end
    assert_equal short_str_b, short_got_b.value
    redis.pipelined do
      long_got_b    = Redis::ScriptManager.eval_gently(redis,long_lua_b,['k'])
    end
    #
    # In TDD style, this final assert fails if the in_pipeline check
    # is disabled in Redis::ScriptManager.eval_gently().
    #
    assert_equal long_str_b,  long_got_b.value   # fails w/o in_pipeline check
    #
    # Confirm via stats that we went covered all salient code paths.
    #
    expect_stats = [
      [:increment, "eval"],
      [:increment, "evalsha1"],
      [:increment, "script_load"],
      [:increment, "evalsha2"],
      [:increment, "eval"],          # short lua always eval
      [:increment, "pipeline_eval"],
    ]
    assert_equal expect_stats, Redis::ScriptManager.configuration.statsd.flush
  end

  def test_implications_of_do_preload
    return if !redis
    Redis::ScriptManager.configuration.do_preload = true
    Redis::ScriptManager.configuration.statsd     = MockStatsd.new
    #
    # everything works fine without a pipeline
    #
    Redis::ScriptManager.purge_preloaded_shas
    max_tiny_lua    = Redis::ScriptManager.configuration.max_tiny_lua
    short_str_a     = 'a' * (max_tiny_lua/10)
    long_str_a      = 'a' * max_tiny_lua
    short_lua_a     = "return '#{short_str_a}'" # not cached, will eval
    long_lua_a      = "return '#{long_str_a}'"  # not cached, will evalsha
    short_got_a     = Redis::ScriptManager.eval_gently(redis,short_lua_a,['k'])
    long_got_a      = Redis::ScriptManager.eval_gently(redis,long_lua_a,['k'])
    assert_equal short_str_a, short_got_a
    assert_equal long_str_a,  long_got_a
    #
    # Everything works the same way with a pipeline.
    #
    short_str_b     = 'b' * (max_tiny_lua/10)
    long_str_b      = 'b' * max_tiny_lua
    short_lua_b     = "return '#{short_str_b}'" # not cached, will eval
    long_lua_b      = "return '#{long_str_b}'"  # not cached, will evalsha
    short_got_b     = nil
    long_got_b      = nil
    redis.pipelined do # triple up to see cache_hit and cache_miss
      short_got_b   = Redis::ScriptManager.eval_gently(redis,short_lua_b,['k'])
      short_got_b   = Redis::ScriptManager.eval_gently(redis,short_lua_b,['k'])
      short_got_b   = Redis::ScriptManager.eval_gently(redis,short_lua_b,['k'])
    end
    assert_equal short_str_b, short_got_b.value
    redis.pipelined do # triple up to see cache_hit and cache_miss
      long_got_b    = Redis::ScriptManager.eval_gently(redis,long_lua_b,['k'])
      long_got_b    = Redis::ScriptManager.eval_gently(redis,long_lua_b,['k'])
      long_got_b    = Redis::ScriptManager.eval_gently(redis,long_lua_b,['k'])
    end
    #
    # In TDD style, this final assert fails if the in_pipeline check
    # is disabled in Redis::ScriptManager.eval_gently().
    #
    assert_equal long_str_b,  long_got_b.value   # fails w/o in_pipeline check
    #
    # Confirm via stats that we went covered all salient code paths.
    #
    # Pipelines have no effect on the flow.  History in preloaded_shas
    # does matter.
    #
    expect_stats = [
      [:increment, "eval"],
      [:increment, "preloaded_shas.cache_miss"],
      [:timing,    "preloaded_shas.cache_size", 1],
      [:increment, "eval"],
      [:increment, "eval"],
      [:increment, "eval"],
      [:increment, "preloaded_shas.cache_miss"],
      [:timing,    "preloaded_shas.cache_size", 2],
      [:increment, "preloaded_shas.cache_hit"],
      [:timing,    "preloaded_shas.cache_size", 2],
      [:increment, "preloaded_shas.cache_hit"],
      [:timing,    "preloaded_shas.cache_size", 2],
    ]
    assert_equal expect_stats, Redis::ScriptManager.configuration.statsd.flush
  end

  # This test suite skips many test if a redis-server is not available.
  #
  # But we consider testing incomplete if that happens.
  #
  # This test directly checks the availability of a redis-server at
  # ENV['REDIS_URL'].
  #
  def test_redis_is_available
    refute_nil   ENV['REDIS_URL'],   "need REDIS_URL for complete test"
    refute_nil   redis,              "need a redis for complete test"
    assert_equal 'PONG', redis.ping, "no redis-server at REDIS_URL"
  end

end
