[![Build Status](https://travis-ci.org/meltwater/gen_rmq.svg?branch=master)](https://travis-ci.org/meltwater/gen_rmq)
[![Hex Version](http://img.shields.io/hexpm/v/gen_rmq.svg)](https://hex.pm/packages/gen_rmq)
[![Coverage Status](https://coveralls.io/repos/github/meltwater/gen_rmq/badge.svg?branch=master)](https://coveralls.io/github/meltwater/gen_rmq?branch=master)

# GenRMQ

GenRMQ is a set of [behaviours][behaviours] meant to be used to create RabbitMQ consumers and publishers.
Internally it is using [AMQP][amqp] elixir RabbitMQ client. The idea is to reduce boilerplate consumer / publisher
code, which usually includes:

* creating connection / channel and keeping it in a state
* creating and binding queue
* handling reconnections / consumer cancellations

The project currently provides the following functionality:

* `GenRMQ.Consumer` - a behaviour for implementing RabbitMQ consumers
* `GenRMQ.Publisher` - a behaviour for implementing RabbitMQ publishers
* `GenRMQ.Processor` - a behaviour for implementing RabbitMQ message processors
* `GenRMQ.RabbitCase` - test utilities for RabbitMQ ([example usage][rabbit_case_example])

## Installation

~~~elixir
def deps do
  [{:gen_rmq, "~> 1.0.0"}]
end
~~~

## Migrating from 0.* to 1.*

Since version `1.0.0` we have updated `amqp` dependency to version `1.0.3`.
This might require some extra steps to configure / disable [lager][lager] in your application.

One of the solutions might be to silence it completely by adding below configuration to
your application config:

~~~elixir
config :lager, :crash_log, false
config :lager, handlers: [level: :critical]
config :lager, :error_logger_redirect, false
config :lager, :error_logger_whitelist, [Logger.ErrorHandler]
~~~

Check more regarding lager and elixir support [here][lager_elixir].

## Examples

More thorough examples for using `GenRMQ.Consumer` and `GenRMQ.Publisher` can be found in the [examples][examples] directory.

### Consumer

~~~elixir
defmodule Consumer do
  @behaviour GenRMQ.Consumer

  def init() do
    [
      queue: "gen_rmq_in_queue",
      exchange: "gen_rmq_exchange",
      routing_key: "#",
      prefetch_count: "10",
      uri: "amqp://guest:guest@localhost:5672",
      retry_delay_function: fn attempt -> :timer.sleep(2000 * attempt) end
    ]
  end

  def consumer_tag() do
    "test_tag"
  end

  def handle_message(message) do
    ...
  end
end
~~~

~~~elixir
GenRMQ.Consumer.start_link(Consumer, name: Consumer)
~~~

This will result in:

* durable `gen_rmq_exchange.deadletter` exchange created or redeclared
* durable `gen_rmq_in_queue_error` queue created or redeclared. It will be bound to `gen_rmq_exchange.deadletter`
* durable topic `gen_rmq_exchange` exchange created or redeclared
* durable `gen_rmq_in_queue` queue created or redeclared. It will be bound to `gen_rmq_exchange` exchange and has a deadletter exchange set to `gen_rmq_exchange.deadletter`
* every `handle_message` callback will executed in separate process. This can be disabled by setting `concurrency: false` in `init` callback
* on failed rabbitmq connection it will wait for a bit and then reconnect

Optionally, you can:

* specify queue ttl with `queue_ttl` attribute
* disable deadletter setup by setting `deadletter` attribute to `false`
* define custom names for deadletter queue / exchange by specifying `deadletter_queue` / `deadletter_exchange` attributes

For all available options please check [consumer documentation][consumer_doc].

### Publisher

~~~elixir
defmodule Publisher do
  @behaviour GenRMQ.Publisher

  def init() do
    [
      exchange: "gen_rmq_exchange",
      uri: "amqp://guest:guest@localhost:5672"
    ]
  end
end
~~~

~~~elixir
GenRMQ.Publisher.start_link(Publisher, name: Publisher)
GenRMQ.Publisher.publish(Publisher, Poison.encode!(%{msg: "msg"}))
~~~

## Running tests

You need [docker-compose][docker_compose] installed.

~~~bash
$ make test
~~~

## How to contribute

We happily accept contributions in the form of [Github PRs][github_prs]
or in the form of bug reports, comments/suggestions or usage questions by creating a [github issue][gen_rmq_issues].

## Notes on project maturity

This library was developed as a Meltwater internal project starting in January 2018.
Over the next two months it has been used in at least three Meltwater production services.

## License

The MIT License (MIT)

Copyright (c) 2018 Meltwater Inc. [http://underthehood.meltwater.com/][underthehood]

[behaviours]: https://hexdocs.pm/elixir/behaviours.html
[amqp]: https://github.com/pma/amqp
[rabbit_case_example]: https://github.com/meltwater/gen_rmq/blob/master/test/gen_rmq_publisher_test.exs
[lager]: https://github.com/pma/amqp/wiki/Upgrade-from-0.X-to-1.0#lager
[lager_elixir]: https://github.com/erlang-lager/lager#elixir-support
[examples]: https://github.com/meltwater/gen_rmq/tree/master/examples
[consumer_doc]: https://github.com/meltwater/gen_rmq/blob/master/lib/consumer.ex
[docker_compose]: https://docs.docker.com/compose/
[github_prs]: https://help.github.com/articles/about-pull-requests/
[gen_rmq_issues]: https://github.com/meltwater/gen_rmq/issues
[underthehood]: http://underthehood.meltwater.com/
