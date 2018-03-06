[![Build Status](https://travis-ci.com/meltwater/gen_amqp.svg?token=JscQvnQYQz7Pr7TwvyZh&branch=master)](https://travis-ci.com/meltwater/gen_amqp)

# GenAMQP

GenAMQP is a set of [behaviours](https://hexdocs.pm/elixir/behaviours.html) meant to be used to create RabbitMQ consumers and publishers.
Internally it is using [AMQP](https://github.com/pma/amqp) elixir RabbitMQ client. The idea is to reduce boilerplate consumer / publisher
code, which usually includes:

* creating connection / channel and keeping it in a state
* creating and binding queue
* handling reconnections / consumer cancellations

The project currently provides the following functionality:

- `GenAMQP.Consumer` - a behaviour for implementing RabbitMQ consumers
- `GenAMQP.Publisher` - a behaviour for implementing RabbitMQ publishers
- `GenAMQP.Processor` - a behaviour for implementing RabbitMQ message processors
- `GenAMQP.RabbitCase` - test utilities for RabbitMQ ([example usage](test/gen_amqp_publisher_test.exs))

## Examples

More thorough examples for using `GenAMQP.Consumer` and `GenAMQP.Publisher` can be found in the [examples](examples) directory.

### Consumer

~~~elixir
defmodule Consumer do
  @behaviour GenAMQP.Consumer

  def init() do
    [
      queue: "gen_amqp_in_queue",
      exchange: "gen_amqp_exchange",
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
GenAMQP.Consumer.start_link(Consumer, name: Consumer)
~~~

This will result in:
* durable `gen_amqp_exchange.deadletter` exchange created or redeclared
* durable `gen_amqp_in_queue_error` queue created or redeclared. It will be bound to `gen_amqp_exchange.deadletter`
* durable `gen_amqp_exchange` exchange created or redeclared
* durable `gen_amqp_in_queue` queue created or redeclared. It will be bound to `gen_amqp_exchange`
exchange and has a deadletter exchange set to `gen_amqp_exchange.deadletter`
* on failed rabbitmq connection it will wait for a bit and then reconnect
* every `handle_message` callback will executed in separate process. This can be disabled by setting `concurrency: false` in `init` callback

For all available options please check [consumer documentation](lib/consumer.ex).

### Publisher

~~~elixir
defmodule Publisher do
  @behaviour GenAMQP.Publisher

  def init() do
    [
      exchange: "gen_amqp_exchange",
      uri: "amqp://guest:guest@localhost:5672"
    ]
  end
end
~~~

~~~elixir
GenAMQP.Publisher.start_link(Publisher, name: Publisher)
GenAMQP.Publisher.publish(Publisher, Poison.encode!(%{msg: "msg"}))
~~~

## Installation
~~~elixir
def deps do
  [
    {
      :gen_amqp,
      git: "git@github.com:meltwater/gen_amqp.git",
      tag: "v0.1.6"
    }
  ]
end
~~~

## Running tests
You need [docker-compose](https://docs.docker.com/compose/) installed.
~~~bash
$ make test
~~~

## How to contribute
We happily accept contributions in the form of [Github PRs](https://help.github.com/articles/about-pull-requests/)
or in the form of bug reports, comments/suggestions or usage questions by creating a [github issue](https://github.com/meltwater/gen_amqp/issues).

## Notes on project maturity
This library was developed as a Meltwater internal project starting in January 2018.
Over the next two months it has been used in at least three Meltwater production services.

## License
The MIT License (MIT)

Copyright (c) 2016 Meltwater Inc. http://underthehood.meltwater.com/

## [Changelog](CHANGELOG.md)
