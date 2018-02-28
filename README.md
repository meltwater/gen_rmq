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
- `GenAMQP.RabbitCase` - test utilities for RabbitMQ ([example usage](test/gen_amqp_test.exs))

## Examples

More thorough examples for using GenAMQP.Consumer and GenAMQP.Publisher can be found in the [examples](examples) directory.

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
      uri: "amqp://guest:guest@localhost:5672"
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
      tag: "v0.1.5"
    }
  ]
end
~~~

## Running tests

You need [docker-compose](https://docs.docker.com/compose/) installed.
~~~bash
$ make test
~~~

## Changelog

### [0.1.5] - 2018-02-28
#### Added
- Possibility to control concurrency in consumer @mkorszun.
- Possibility to make `app_id` configurable for publisher @mkorszun.
- Better `ExDoc` documentation

#### Fixed
- If `queue_ttl` specified it also applies to dead letter queue @mkorszun.
- Default `routing_key` on publish

### [0.1.4] - 2018-02-06
#### Added
- Possibility to specify queue ttl in consumer config @mkorszun.

### [0.1.3] - 2018-01-31
#### Added
- Processor behaviour @mkorszun.
#### Removed
- Unused test helper functions @mkorszun.

[0.1.4]: https://github.com/meltwater/gen_amqp/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/meltwater/gen_amqp/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/meltwater/gen_amqp/compare/v0.1.2...v0.1.3
