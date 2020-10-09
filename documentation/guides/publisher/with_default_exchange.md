Publisher with default exchange
===============================

> [The default exchange](https://www.rabbitmq.com/tutorials/amqp-concepts.html#exchange-default) is a direct exchange with no name (empty string) pre-declared by the broker. It has one special property that makes it very useful for simple applications: every queue that is created is automatically bound to it with a routing key which is the same as the queue name.

# Example

~~~elixir
defmodule WithDefaultExchange do
  @behaviour GenRMQ.Publisher

  def start_link() do
    GenRMQ.Publisher.start_link(__MODULE__, name: __MODULE__)
  end

  def publish_message(message, routing_key) do
    Logger.info("Publishing message #{inspect(message)}")
    GenRMQ.Publisher.publish(__MODULE__, message, routing_key)
  end

  def init() do
    [
      exchange: :default,
      connection: "amqp://guest:guest@localhost:5672"
    ]
  end
end
~~~