[![Build Status](https://travis-ci.org/meltwater/gen_rmq.svg?branch=master)](https://travis-ci.org/meltwater/gen_rmq)
[![Hex Version](http://img.shields.io/hexpm/v/gen_rmq.svg)](https://hex.pm/packages/gen_rmq)
[![Coverage Status](https://coveralls.io/repos/github/meltwater/gen_rmq/badge.svg?branch=master)](https://coveralls.io/github/meltwater/gen_rmq?branch=master)
[![Hex.pm Download Total](https://img.shields.io/hexpm/dt/gen_rmq.svg?style=flat-square)](https://hex.pm/packages/gen_rmq)
[![Dependabot Status](https://api.dependabot.com/badges/status?host=github&repo=meltwater/gen_rmq)](https://dependabot.com)

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
  [{:gen_rmq, "~> 1.3.0"}]
end
~~~

## Migrations

Please check [how to migrate to gen_rmq `1.0.0`][migrating_to_100] from previous versions.

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

There are many options to control the consumer setup details, please check the `c:GenRMQ.Consumer.init/0` [docs][consumer_doc] for all available settings.

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
GenRMQ.Publisher.publish(Publisher, Jason.encode!(%{msg: "msg"}))
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
[migrating_to_100]: https://github.com/meltwater/gen_rmq/wiki/Migrations#0---100
[examples]: https://github.com/meltwater/gen_rmq/tree/master/examples
[consumer_doc]: https://github.com/meltwater/gen_rmq/blob/master/lib/consumer.ex
[docker_compose]: https://docs.docker.com/compose/
[github_prs]: https://help.github.com/articles/about-pull-requests/
[gen_rmq_issues]: https://github.com/meltwater/gen_rmq/issues
[priority_queues]: https://www.rabbitmq.com/priority.html
[underthehood]: http://underthehood.meltwater.com/
