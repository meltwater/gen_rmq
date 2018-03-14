[![Build Status](https://travis-ci.org/meltwater/gen_rmq.svg?branch=master)](https://travis-ci.org/meltwater/gen_rmq)
[![Coverage Status](https://coveralls.io/repos/github/meltwater/gen_rmq/badge.svg?branch=master)](https://coveralls.io/github/meltwater/gen_rmq?branch=master)

# GenRMQ

GenRMQ is a set of [behaviours](https://hexdocs.pm/elixir/behaviours.html) meant to be used to create RabbitMQ consumers and publishers.
Internally it is using [AMQP](https://github.com/pma/amqp) elixir RabbitMQ client. The idea is to reduce boilerplate consumer / publisher
code, which usually includes:

* creating connection / channel and keeping it in a state
* creating and binding queue
* handling reconnections / consumer cancellations

The project currently provides the following functionality:

- `GenRMQ.Consumer` - a behaviour for implementing RabbitMQ consumers
- `GenRMQ.Publisher` - a behaviour for implementing RabbitMQ publishers
- `GenRMQ.Processor` - a behaviour for implementing RabbitMQ message processors
- `GenRMQ.RabbitCase` - test utilities for RabbitMQ ([example usage](test/gen_rmq_publisher_test.exs))

## Installation
~~~elixir
def deps do
  [{:gen_rmq, "~> 0.1.7"}]
end
~~~

## Examples

More thorough examples for using `GenRMQ.Consumer` and `GenRMQ.Publisher` can be found in the [examples](examples) directory.

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
* durable `gen_rmq_exchange` exchange created or redeclared
* durable `gen_rmq_in_queue` queue created or redeclared. It will be bound to `gen_rmq_exchange`
exchange and has a deadletter exchange set to `gen_rmq_exchange.deadletter`
* every `handle_message` callback will executed in separate process. This can be disabled by setting `concurrency: false` in `init` callback
* on failed rabbitmq connection it will wait for a bit and then reconnect

For all available options please check [consumer documentation](lib/consumer.ex).

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
You need [docker-compose](https://docs.docker.com/compose/) installed.
~~~bash
$ make test
~~~

## How to contribute
We happily accept contributions in the form of [Github PRs](https://help.github.com/articles/about-pull-requests/)
or in the form of bug reports, comments/suggestions or usage questions by creating a [github issue](https://github.com/meltwater/gen_rmq/issues).

## Notes on project maturity
This library was developed as a Meltwater internal project starting in January 2018.
Over the next two months it has been used in at least three Meltwater production services.

## License
The MIT License (MIT)

Copyright (c) 2016 Meltwater Inc. http://underthehood.meltwater.com/
