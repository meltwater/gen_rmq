[![Build Status](https://travis-ci.com/meltwater/gen_amqp.svg?token=JscQvnQYQz7Pr7TwvyZh&branch=master)](https://travis-ci.com/meltwater/gen_amqp)

# GenAmqp

GenAmqp is a set of behaviours meant to be used to create RabbitMQ consumers and publishers.

The project currently provides the following functionality:

- `GenAMQP.Consumer` - a behaviour for implementing RabbitMQ consumers
- `GenAMQP.Publisher` - a behaviour for implementing RabbitMQ publishers
- `GenAMQP.RabbitCase` - test utilities for RabbitMQ ([example usage](test/gen_amqp_test.exs))

## Examples

More thorough examples for using GenAMQP.Consumer and GenAMQP.Publisher can be found in the [examples](examples) directory.

### Consumer

~~~elixir
defmodule Consumer do
  @behaviour GenAMQP.Consumer

  def init(_state) do
    [
      queue: "gen_amqp_in_queue",
      exchange: "gen_amqp_exchange",
      routing_key: "#",
      prefetch_count: "10",
      uri: "amqp://guest:guest@localhost:5672"
    ]
  end

  def consumer_tag(n) do
    "test_tag_#{n}"
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

  def init(_state) do
    [
      exchange: "gen_amqp_exchange",
      uri: "amqp://guest:guest@localhost:5672",
      routing_key: "#"
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
      tag: "v0.1.1"
    }
  ]
end
~~~

## Running tests

You need [docker-compose](https://docs.docker.com/compose/) installed.

    make test
