defmodule GenRMQ.Consumer do
  @moduledoc """
  A behaviour module for implementing the RabbitMQ consumer.

  It will:
  * setup RabbitMQ connection / channel and keep them in a state
  * create (if does not exist) a queue and bind it to an exchange
  * create deadletter queue and exchange
  * handle reconnections
  * call `handle_message` callback on every message delivery
  """

  use GenServer
  use AMQP

  require Logger
  alias GenRMQ.Message

  ##############################################################################
  # GenRMQ.Consumer callbacks
  ##############################################################################

  @doc """
  Invoked to provide consumer configuration

  ## Return values
  ### Mandatory:

  `uri` - RabbitMQ uri

  `queue` - the name of the queue to consume.
  If does not exist it will be created

  `exchange` - the name of the exchange to which `queue` should be bind.
  If does not exist it will be created

  `routing_key` - queue binding key

  `prefetch_count` - limit the number of unacknowledged messages

  ### Optional:

  `queue_ttl` - controls for how long a queue can be unused before it is
  automatically deleted. Unused means the queue has no consumers,
  the queue has not been redeclared, and basic.get has not been invoked
  for a duration of at least the expiration period

  `concurrency` - defines if `handle_message` callback is called
  in seperate process using [spawn](https://hexdocs.pm/elixir/Process.html#spawn/2)
  function. By default concurrency is enabled. To disable, set it to `false`

  `retry_delay_function` - custom retry delay function. Called when the connection to
  the broker cannot be established. Receives the connection attempt as an argument (>= 1)
  and is expected to wait for some time.
  With this callback you can for example do exponential backoff.
  The default implementation is a linear delay starting with 1 second step.

  `reconnect` - defines if consumer should reconnect on connection termination.
  By default reconnection is enabled.

  `deadletter` - defines if consumer should setup deadletter exchange and queue.

  `deadletter_queue` - defines name of the deadletter queue.

  `deadletter_exchange` - defines name of the deadletter exchange.

  ## Examples:
  ```
  def init() do
    [
      queue: "gen_rmq_in_queue",
      exchange: "gen_rmq_exchange",
      routing_key: "#",
      prefetch_count: "10",
      uri: "amqp://guest:guest@localhost:5672",
      concurrency: true,
      queue_ttl: 5000,
      retry_delay_function: fn attempt -> :timer.sleep(1000 * attempt) end,
      reconnect: true,
      deadletter: true,
      deadletter_queue: "gen_rmq_in_queue_error",
      deadletter_exchange: "gen_rmq_exchange.deadletter"
    ]
  end
  ```

  """
  @callback init() :: [
              queue: String.t(),
              exchange: String.t(),
              routing_key: String.t(),
              prefetch_count: String.t(),
              uri: String.t(),
              concurrency: Boolean.t(),
              queue_ttl: Integer.t(),
              retry_delay_function: Function.t(),
              reconnect: Booleam.t(),
              deadletter: Boolean.t(),
              deadletter_queue: String.t(),
              deadletter_exchange: String.t()
            ]

  @doc """
  Invoked to provide consumer [tag](https://www.rabbitmq.com/amqp-0-9-1-reference.html#domain.consumer-tag)

  ## Examples:
  ```
  def consumer_tag() do
    "hostname-app-version-consumer"
  end
  ```

  """
  @callback consumer_tag() :: String.t()

  @doc """
  Invoked on message delivery

  `message` - `GenRMQ.Message` struct

  ## Examples:
  ```
  def handle_message(message) do
    # Do something with message and acknowledge it
    GenRMQ.Consumer.ack(message)
  end
  ```

  """
  @callback handle_message(message :: GenRMQ.Message.t()) :: :ok

  ##############################################################################
  # GenRMQ.Consumer API
  ##############################################################################

  @doc """
  Starts `GenRMQ.Consumer` process with given callback module linked to the current
  process

  `module` - callback module implementing `GenRMQ.Consumer` behaviour

  ## Options
   * `:name` - used for name registration

  ## Return values
  If the consumer is successfully created and initialized, this function returns
  `{:ok, pid}`, where `pid` is the PID of the consumer. If a process with the
  specified consumer name already exists, this function returns
  `{:error, {:already_started, pid}}` with the PID of that process.

  ## Examples:
  ```
  GenRMQ.Consumer.start_link(Consumer, name: :consumer)
  ```

  """
  @spec start_link(module :: Module.t(), options :: Keyword.t()) :: {:ok, Pid.t()} | {:error, Any.t()}
  def start_link(module, options \\ []) do
    GenServer.start_link(__MODULE__, %{module: module}, options)
  end

  @doc """
  Synchronously stops the consumer with a given reason

  `name` - pid or name of the consumer to stop
  `reason` - reason of the termination

  ## Examples:
  ```
  GenRMQ.Consumer.stop(:consumer, :normal)
  ```

  """
  @spec stop(name :: Atom.t() | Pit.t(), reason :: Any.t()) :: :ok
  def stop(name, reason) do
    GenServer.stop(name, reason)
  end

  @doc """
  Acknowledges given message

  `message` - `GenRMQ.Message` struct
  """
  @spec ack(message :: GenRMQ.Message.t()) :: :ok
  def ack(%Message{state: %{in: channel}, attributes: %{delivery_tag: tag}}) do
    Basic.ack(channel, tag)
  end

  @doc """
  Requeues / rejects given message

  `message` - `GenRMQ.Message` struct

  `requeue` - indicates if message should be requeued
  """
  @spec reject(message :: GenRMQ.Message.t(), requeue :: Boolean.t()) :: :ok
  def reject(%Message{state: %{in: channel}, attributes: %{delivery_tag: tag}}, requeue \\ false) do
    Basic.reject(channel, tag, requeue: requeue)
  end

  ##############################################################################
  # GenServer callbacks
  ##############################################################################

  @doc false
  def init(%{module: module} = initial_state) do
    config = apply(module, :init, [])

    state =
      initial_state
      |> Map.put(:config, config)
      |> Map.put(:reconnect_attempt, 0)
      |> get_connection()
      |> open_channels()
      |> setup_consumer()

    {:ok, state}
  end

  @doc false
  def handle_call({:recover, requeue}, _from, %{in: channel} = state) do
    {:reply, Basic.recover(channel, requeue: requeue), state}
  end

  @doc false
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{module: module, config: config} = state) do
    Logger.info("[#{module}]: RabbitMQ connection is down! Reason: #{inspect(reason)}")

    config
    |> Keyword.get(:reconnect, true)
    |> handle_reconnect(state)
  end

  @doc false
  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, %{module: module} = state) do
    Logger.info("[#{module}]: Broker confirmed consumer with tag #{consumer_tag}")
    {:noreply, state}
  end

  @doc false
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, %{module: module} = state) do
    Logger.warn("[#{module}]: The consumer was unexpectedly cancelled, tag: #{consumer_tag}")
    {:stop, :cancelled, state}
  end

  @doc false
  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, %{module: module} = state) do
    Logger.info("[#{module}]: Consumer was cancelled, tag: #{consumer_tag}")
    {:noreply, state}
  end

  @doc false
  def handle_info({:basic_deliver, payload, attributes}, %{module: module, config: config} = state) do
    %{delivery_tag: tag, routing_key: routing_key, redelivered: redelivered} = attributes
    Logger.debug("[#{module}]: Received message. Tag: #{tag}, routing key: #{routing_key}, redelivered: #{redelivered}")

    if redelivered do
      Logger.debug("[#{module}]: Redelivered payload for message. Tag: #{tag}, payload: #{payload}")
    end

    handle_message(payload, attributes, state, Keyword.get(config, :concurrency, true))

    {:noreply, state}
  end

  @doc false
  def terminate(:connection_closed = reason, %{module: module}) do
    # Since connection has been closed no need to clean it up
    Logger.debug("[#{module}]: Terminating consumer, reason: #{inspect(reason)}")
  end

  @doc false
  def terminate(reason, %{module: module, conn: conn}) do
    Logger.debug("[#{module}]: Terminating consumer, reason: #{inspect(reason)}")
    AMQP.Connection.close(conn)
  end

  ##############################################################################
  # Helpers
  ##############################################################################

  defp handle_message(payload, attributes, %{module: module} = state, false) do
    message = Message.create(attributes, payload, state)
    apply(module, :handle_message, [message])
  end

  defp handle_message(payload, attributes, %{module: module} = state, true) do
    spawn(fn ->
      message = Message.create(attributes, payload, state)
      apply(module, :handle_message, [message])
    end)
  end

  defp handle_reconnect(false, %{module: module} = state) do
    Logger.info("[#{module}]: Reconnection is disabled. Terminating consumer.")
    {:stop, :connection_closed, state}
  end

  defp handle_reconnect(_, state) do
    new_state =
      state
      |> Map.put(:reconnect_attempt, 0)
      |> get_connection()
      |> open_channels()
      |> setup_consumer()

    {:noreply, new_state}
  end

  defp get_connection(%{config: config, module: module, reconnect_attempt: attempt} = state) do
    case Connection.open(config[:uri]) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        Map.put(state, :conn, conn)

      {:error, e} ->
        Logger.error(
          "[#{module}]: Failed to connect to RabbitMQ with settings: " <>
            "#{inspect(strip_key(config, :uri))}, reason #{inspect(e)}"
        )

        retry_delay_fn = config[:retry_delay_function] || (&linear_delay/1)
        next_attempt = attempt + 1
        retry_delay_fn.(next_attempt)

        state
        |> Map.put(:reconnect_attempt, next_attempt)
        |> get_connection()
    end
  end

  defp open_channels(%{conn: conn} = state) do
    {:ok, chan} = Channel.open(conn)
    {:ok, out_chan} = Channel.open(conn)
    Map.merge(state, %{in: chan, out: out_chan})
  end

  defp setup_consumer(%{in: chan, config: config, module: module} = state) do
    queue = config[:queue]
    exchange = config[:exchange]
    routing_key = config[:routing_key]
    prefetch_count = String.to_integer(config[:prefetch_count])
    ttl = config[:queue_ttl]

    deadletter_args = setup_deadletter(chan, config)
    arguments = deadletter_args |> setup_ttl(ttl)

    Basic.qos(chan, prefetch_count: prefetch_count)
    Queue.declare(chan, queue, durable: true, arguments: arguments)
    Exchange.topic(chan, exchange, durable: true)
    Queue.bind(chan, queue, exchange, routing_key: routing_key)

    consumer_tag = apply(module, :consumer_tag, [])
    {:ok, _consumer_tag} = Basic.consume(chan, queue, nil, consumer_tag: consumer_tag)
    state
  end

  defp setup_deadletter(chan, config) do
    case Keyword.get(config, :deadletter, true) do
      true ->
        ttl = config[:queue_ttl]
        queue = config[:queue]
        exchange = config[:exchange]
        dl_queue = config[:deadletter_queue] || "#{queue}_error"
        dl_exchange = config[:deadletter_queue] || "#{exchange}.deadletter"

        Queue.declare(chan, dl_queue, durable: true, arguments: setup_ttl([], ttl))
        Exchange.topic(chan, dl_exchange, durable: true)
        Queue.bind(chan, dl_queue, dl_exchange, routing_key: "#")

        [{"x-dead-letter-exchange", :longstr, dl_exchange}]

      false ->
        []
    end
  end

  defp strip_key(keyword_list, key) do
    keyword_list
    |> Keyword.delete(key)
    |> Keyword.put(key, "[FILTERED]")
  end

  defp linear_delay(attempt), do: :timer.sleep(attempt * 1_000)

  defp setup_ttl(arguments, nil), do: arguments
  defp setup_ttl(arguments, ttl), do: [{"x-expires", :long, ttl} | arguments]

  ##############################################################################
  ##############################################################################
  ##############################################################################
end
