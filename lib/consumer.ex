defmodule GenAMQP.Consumer do
  @moduledoc """
  Defines generic behaviour for AMQP consumer.
  """

  use GenServer
  use AMQP

  require Logger
  alias Scribe.AMQP.Message

  ##############################################################################
  # GenConsumer callbacks
  ##############################################################################

  @doc "Should provide consumer config"
  @callback init(Any.t) :: Keyword.t

  @doc "Should provide consumer tag"
  @callback consumer_tag(Any.t) :: String.t

  @doc "Should handle received message"
  @callback handle_message(Message.t) :: :ok

  ##############################################################################
  # GenConsumer API
  ##############################################################################

  @doc "Starts amqp consumer"
  def start_link(module, opts \\ []) do
    GenServer.start_link(__MODULE__, %{module: module}, opts)
  end

  ##############################################################################
  # GenServer callbacks
  ##############################################################################

  def init(%{module: module} = initial_state) do
    config = apply(module, :init, [initial_state])

    initial_state
    |> Map.merge(%{config: config})
    |> rabbitmq_connect
  end

  def handle_call({:recover, requeue}, _from, %{in: channel} = state) do
    {:reply, Basic.recover(channel, [requeue: requeue]), state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{module: module} = state) do
    Logger.info("[#{module}]: RabbitMQ connection is down! Reason: #{inspect reason}")
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

  def handle_info({:basic_deliver,
                   payload,
                   %{delivery_tag: tag,
                     routing_key: routing_key,
                     redelivered: redelivered
                   } = attributes
                  },
                  %{module: module} = state) do
    Logger.debug("[#{module}]: Received message. Tag: #{tag}, " <>
      "routing key: #{routing_key}, redelivered: #{redelivered}")

    if redelivered do
      Logger.debug("[#{module}]: Redelivered payload for message. Tag: #{tag}, payload: #{payload}")
    end

    spawn fn ->
      message = Message.create(attributes, payload, state)
      apply(module, :handle_message, [message])
    end

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
        consumer_tag = apply(module, :consumer_tag, [1])

        {:ok, _consumer_tag} = Basic.consume(chan, queue, nil, [consumer_tag: consumer_tag])
        {:ok, %{in: chan, out: out_chan, conn: conn, config: config, module: module}}
      {:error, e} ->
        Logger.error("[#{module}]: Failed to connect to RabbitMQ with settings: " <>
          "#{inspect strip_key(config, :uri)}, reason #{inspect e}")
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
    prefetch_count = config |> Keyword.get(:prefetch_count) |> String.to_integer
    queue_error = "#{queue}_error"
    exchange_error = "#{exchange}.deadletter"
    arguments = [{"x-dead-letter-exchange", :longstr, exchange_error}]

    setup_deadletter(chan, exchange_error, queue_error)
    Basic.qos(chan, prefetch_count: prefetch_count)
    Queue.declare(chan, queue, durable: true, arguments: arguments)
    Exchange.topic(chan, exchange, durable: true)
    Queue.bind(chan, queue, exchange, [routing_key: routing_key])
    queue
  end

  defp setup_deadletter(chan, dl_exchange, dl_queue) do
    Queue.declare(chan, dl_queue, durable: true)
    Exchange.topic(chan, dl_exchange, durable: true)
    Queue.bind(chan, dl_queue, dl_exchange, [routing_key: "#"])
  end

  ##############################################################################
  ##############################################################################
  ##############################################################################
end
