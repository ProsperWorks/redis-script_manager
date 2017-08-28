# Redis::ScriptManager

Redis::ScriptManager executes your Lua scripts in your Redis
infrastructure while managing trade-offs between bandwidth and
statefulness.

## Other Packages With Related Functionality

### resque-scheduler

https://github.com/resque/resque-scheduler

Resque::Scheduler::Lock::Resiliant manages its scripts with
load-on-init and EVALSHA-else-SCRIPT-LOAD-and-re-EVALSHA.

This is robust if there are no SCRIPT FLUSH or no pipelines, but it
will fail if a SCRIPT FLUSH can happen after init, then we run in a
pipeline.

The Lua scripts in resque-scheduler are only a few 100s of bytes in
size, so there is little to be gained by avoiding simply using EVAL.

Warning: resque-scheduler embeds "#{timeout}" in its Lua scripts.  One
is unlikely to change resque-scheduler lock timeouts frequently, but
if so it could be possible to fill the Redis script cache with tons of
abandoned scripts.

### wolverine

https://github.com/Shopify/wolverine
http://shopify.github.io/wolverine/

Wolverine does load-on-init and EVALSHA-only.  Assuming you have only
one Redis connection and SCRIPT FLUSH is never called, this is fine
even in a pipeline.

If you juggle multiple Redis connections or are worried about
inconsistent script cache contents, Wolverine might have some gaps.

Wolverine also has nice support for keeping your Lua scripts in a
repository of related .lua files, with support for common code
folding.

### redis-lua

https://github.com/chanks/redis-lua

Redis-lua does EVALSHA-else-SCRIPT-LOAD-and-re-EVALSHA when not in a
pipeline, simple EVAL otherwise.

This is great: this is always correct regardless of how many Redises
you are talking to, and calls outside of a pipeline will tend toward
minimal bandwith as the script cache gets warmed up.

However, if most of your scripting is done within a pipeline,
bandwidth use will stay high.

Early iterations of redis-script_manager were inspired by redis-lua.

### redis-rb-scripting

https://github.com/codekitchen/redis-rb-scripting

redis-rb-scripting does load-on-init plus EVALSHA-else-EVAL.  It is
correct when the script cache is inconsistent but does not tend to
repopulate the cache in these cases.

redis-rb-scripting has no special provision for pipelines.  Called in
a pipeline it will fail to recover from a cold cache.

Like wolverine, redis-rb-scripting also supports a repository of .lua
files, but without the common code folding.

### led

https://github.com/ciconia/led

Like redis-rb-scripting, led does load-on-init plus EVALSHA-else-EVAL.
It is correct when the script cache is inconsistent but does not tend
to repopulate the cache in these cases.  It has no special provision
for pipelines.  Called in a pipeline it will fail to recover from a
cold cache.

Like wolverine, redis-rb-scripting also supports a repository of .lua
files with common code folding.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'redis-script_manager'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install redis-script_manager

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install
dependencies. Then, run `rake test` to run the tests. You can also run
`bin/console` for an interactive prompt that will allow you to
experiment.

To install this gem onto your local machine, run `bundle exec rake
install`. To release a new version, update the version number in
`version.rb`, and then run `bundle exec rake release`, which will
create a git tag for the version, push git commits and tags, and push
the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/[USERNAME]/redis-script_manager.

