defmodule GenAMQP.Consumer do
  @moduledoc """
  Defines generic behaviour for AMQP consumer.
  """

  use GenServer
  use AMQP

  require Logger
  alias GenAMQP.Message

  ##############################################################################
  # GenConsumer callbacks
  ##############################################################################

  @doc """
  Invoked to provide consumer configuration.

  `initial_state` is the state consumer has been started with

  Example:

    def init(_state) do
      [
        queue: "gen_amqp_in_queue",
        exchange: "gen_amqp_exchange",
        routing_key: "#",
        prefetch_count: "10",
        uri: "amqp://guest:guest@localhost:5672"
      ]
    end

  """
  @callback init() :: [
              queue: String.t(),
              exchange: String.t(),
              routing_key: String.t(),
              prefetch_count: String.t(),
              uri: String.t()
            ]

  @doc """
  Invoked to provide consumer [tag](https://www.rabbitmq.com/amqp-0-9-1-reference.html#domain.consumer-tag)

  Example:

    def consumer_tag() do
      "hostname-app-version-consumer"
    end

  """
  @callback consumer_tag() :: String.t()

  @doc """
  Invoked on message delivery

  `message` is the GenAMQP.Message struct. Contains payload,
  attributes and consumer state

  Example:
    def handle_message(message) do
      # Do something with message and acknowledge it
      GenAMQP.Consumer.ack(message)
    end

  """
  @callback handle_message(message :: Message.t()) :: :ok

  ##############################################################################
  # GenConsumer API
  ##############################################################################

  @doc """
  Starts GenAMQP.Consumer with given callback module linked to the current
  process

  `module` is the callback module implementing GenAMQP.Consumer behaviour

  ## Options
   * `:name` - used for name registration

  ## Return values
  If the consumer is successfully created and initialized, this function returns
  `{:ok, pid}`, where `pid` is the PID of the consumer. If a process with the
  specified consumer name already exists, this function returns
  `{:error, {:already_started, pid}}` with the PID of that process.

  Example:
    GenAMQP.Consumer.start_link(TestConsumer, name: :consumer)

  """
  def start_link(module, options \\ []) do
    GenServer.start_link(__MODULE__, %{module: module}, options)
  end

  @doc """
  Acknowledges given message

  `message` is the GenAMQP.Message struct. Contains payload,
  attributes and consumer state
  """
  def ack(%Message{state: %{in: channel}, attributes: %{delivery_tag: tag}}) do
    Basic.ack(channel, tag)
  end

  @doc """
  Requeues / rejects given message

  `message` is the GenAMQP.Message struct. Contains payload,
  attributes and consumer state

  `requeue` indicates if message should be requeued
  """
  def reject(%Message{state: %{in: channel}, attributes: %{delivery_tag: tag}}, requeue \\ false) do
    Basic.reject(channel, tag, requeue: requeue)
  end

  ##############################################################################
  # GenServer callbacks
  ##############################################################################

  def init(%{module: module} = initial_state) do
    config = apply(module, :init, [])

    initial_state
    |> Map.merge(%{config: config})
    |> rabbitmq_connect
  end

  def handle_call({:recover, requeue}, _from, %{in: channel} = state) do
    {:reply, Basic.recover(channel, requeue: requeue), state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{module: module} = state) do
    Logger.info("[#{module}]: RabbitMQ connection is down! Reason: #{inspect(reason)}")
    {:ok, new_state} = rabbitmq_connect(state)
    {:noreply, new_state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, %{module: module} = state) do
    Logger.info("[#{module}]: Broker confirmed consumer with tag #{consumer_tag}")
    {:noreply, state}
  end

  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, %{module: module} = state) do
    Logger.warn("[#{module}]: The consumer was unexpectedly cancelled, tag: #{consumer_tag}")
    {:stop, :normal, state}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, %{module: module} = state) do
    Logger.info("[#{module}]: Consumer was cancelled, tag: #{consumer_tag}")
    {:noreply, state}
  end

  def handle_info(
        {:basic_deliver, payload,
         %{delivery_tag: tag, routing_key: routing_key, redelivered: redelivered} = attributes},
        %{module: module} = state
      ) do
    Logger.debug(
      "[#{module}]: Received message. Tag: #{tag}, " <>
        "routing key: #{routing_key}, redelivered: #{redelivered}"
    )

    if redelivered do
      Logger.debug(
        "[#{module}]: Redelivered payload for message. Tag: #{tag}, payload: #{payload}"
      )
    end

    spawn(fn ->
      message = Message.create(attributes, payload, state)
      apply(module, :handle_message, [message])
    end)

    {:noreply, state}
  end

  ##############################################################################
  # Helpers
  ##############################################################################

  defp rabbitmq_connect(%{config: config, module: module} = state) do
    rabbit_uri = config |> Keyword.get(:uri)

    case Connection.open(rabbit_uri) do
      {:ok, conn} ->
        Process.monitor(conn.pid)

        {:ok, chan} = Channel.open(conn)
        {:ok, out_chan} = Channel.open(conn)

        queue = setup_rabbit(chan, config)
        consumer_tag = apply(module, :consumer_tag, [])

        {:ok, _consumer_tag} = Basic.consume(chan, queue, nil, consumer_tag: consumer_tag)
        {:ok, %{in: chan, out: out_chan, conn: conn, config: config, module: module}}

      {:error, e} ->
        Logger.error(
          "[#{module}]: Failed to connect to RabbitMQ with settings: " <>
            "#{inspect(strip_key(config, :uri))}, reason #{inspect(e)}"
        )

        :timer.sleep(5000)
        rabbitmq_connect(state)
    end
  end

  defp strip_key(keyword_list, key) do
    keyword_list
    |> Keyword.delete(key)
    |> Keyword.put(key, "[FILTERED]")
  end

  defp setup_rabbit(chan, config) do
    queue = config |> Keyword.get(:queue)
    exchange = config |> Keyword.get(:exchange)
    routing_key = config |> Keyword.get(:routing_key)
    prefetch_count = config |> Keyword.get(:prefetch_count) |> String.to_integer()
    ttl = config |> Keyword.get(:queue_ttl)
    queue_error = "#{queue}_error"
    exchange_error = "#{exchange}.deadletter"

    arguments =
      [{"x-dead-letter-exchange", :longstr, exchange_error}]
      |> setup_ttl(ttl)

    setup_deadletter(chan, exchange_error, queue_error)
    Basic.qos(chan, prefetch_count: prefetch_count)
    Queue.declare(chan, queue, durable: true, arguments: arguments)
    Exchange.topic(chan, exchange, durable: true)
    Queue.bind(chan, queue, exchange, routing_key: routing_key)
    queue
  end

  defp setup_ttl(arguments, nil), do: arguments
  defp setup_ttl(arguments, ttl), do: [{"x-expires", :long, ttl} | arguments]

  defp setup_deadletter(chan, dl_exchange, dl_queue) do
    Queue.declare(chan, dl_queue, durable: true)
    Exchange.topic(chan, dl_exchange, durable: true)
    Queue.bind(chan, dl_queue, dl_exchange, routing_key: "#")
  end

  ##############################################################################
  ##############################################################################
  ##############################################################################
end
