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
  alias GenRMQ.Consumer.QueueConfiguration

  ##############################################################################
  # GenRMQ.Consumer callbacks
  ##############################################################################

  @doc """
  Invoked to provide consumer configuration

  ## Return values
  ### Mandatory:

  `connection` - RabbitMQ connection options. Accepts same arguments as AMQP-library's [Connection.open/2](https://hexdocs.pm/amqp/AMQP.Connection.html#open/2).

  `queue` - the name of the queue to consume. If it does not exist, it will be created.

  `exchange` - Name or `{type, name}` of the exchange to which `queue` should be bound. If it does not exist, it will be created.
  For valid exchange types see `GenRMQ.Binding`.

  `routing_key` - queue binding key, can also be a list.

  `prefetch_count` - limit the number of unacknowledged messages.

  ### Optional:

  `uri` - RabbitMQ uri. Deprecated. Please use `connection`.

  `queue_ttl` - controls for how long a queue can be unused before it is
  automatically deleted. Unused means the queue has no consumers,
  the queue has not been redeclared, and basic.get has not been invoked
  for a duration of at least the expiration period

  `queue_max_priority` - defines if a declared queue should be a priority queue.
  Should be set to a value from `1..255` range. If it is greater than `255`, queue
  max priority will be set to `255`. Values between `1` and `10` are
  [recommened](https://www.rabbitmq.com/priority.html#resource-usage).

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

  `deadletter_queue` - defines name of the deadletter queue (**Default:** Same as queue name suffixed by `_error`).

  `deadletter_exchange` - defines name of the deadletter exchange (**Default:** Same as exchange name suffixed by `.deadletter`).

  `deadletter_routing_key` - defines name of the deadletter routing key (**Default:** `#`).

  ## Examples:
  ```
  def init() do
    [
      connection: "amqp://guest:guest@localhost:5672",
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
      deadletter_exchange: "gen_rmq_exchange.deadletter",
      deadletter_routing_key: "#",
      queue_max_priority: 10
    ]
  end
  ```

  """
  @callback init() :: [
              connection: keyword | {String.t(), String.t()} | :undefined | keyword,
              queue: String.t(),
              exchange: GenRMQ.Binding.exchange(),
              routing_key: [String.t()] | String.t(),
              prefetch_count: String.t(),
              uri: String.t(),
              concurrency: boolean,
              queue_ttl: integer,
              retry_delay_function: function,
              reconnect: boolean,
              deadletter: boolean,
              deadletter_queue: String.t(),
              deadletter_exchange: String.t(),
              deadletter_routing_key: String.t(),
              queue_max_priority: integer
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
  @callback handle_message(message :: %GenRMQ.Message{}) :: :ok

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
  @spec start_link(module :: module(), options :: Keyword.t()) :: {:ok, pid} | {:error, term}
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
  @spec stop(name :: atom | pid, reason :: term) :: :ok
  def stop(name, reason) do
    GenServer.stop(name, reason)
  end

  @doc """
  Acknowledges given message

  `message` - `GenRMQ.Message` struct
  """
  @spec ack(message :: %GenRMQ.Message{}) :: :ok
  def ack(%Message{state: %{in: channel}, attributes: %{delivery_tag: tag}} = message) do
    emit_message_ack_event(message)

    Basic.ack(channel, tag)
  end

  @doc """
  Requeues / rejects given message

  `message` - `GenRMQ.Message` struct

  `requeue` - indicates if message should be requeued
  """
  @spec reject(message :: %GenRMQ.Message{}, requeue :: boolean) :: :ok
  def reject(%Message{state: %{in: channel}, attributes: %{delivery_tag: tag}} = message, requeue \\ false) do
    emit_message_reject_event(message, requeue)

    Basic.reject(channel, tag, requeue: requeue)
  end

  ##############################################################################
  # GenServer callbacks
  ##############################################################################

  @doc false
  @impl GenServer
  def init(%{module: module} = initial_state) do
    Process.flag(:trap_exit, true)
    config = apply(module, :init, [])

    parsed_config = parse_config(config)

    state =
      initial_state
      |> Map.put(:config, parsed_config)
      |> Map.put(:reconnect_attempt, 0)

    send(self(), :init)

    {:ok, state}
  end

  @doc false
  @impl GenServer
  def handle_call({:recover, requeue}, _from, %{in: channel} = state) do
    {:reply, Basic.recover(channel, requeue: requeue), state}
  end

  @doc false
  @impl GenServer
  def handle_info(:init, state) do
    state =
      state
      |> get_connection()
      |> open_channels()
      |> setup_consumer()

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{module: module, config: config} = state) do
    Logger.info("[#{module}]: RabbitMQ connection is down! Reason: #{inspect(reason)}")

    emit_connection_down_event(module, reason)

    config
    |> Keyword.get(:reconnect, true)
    |> handle_reconnect(state)
  end

  @doc false
  @impl GenServer
  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, %{module: module} = state) do
    Logger.info("[#{module}]: Broker confirmed consumer with tag #{consumer_tag}")
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, %{module: module} = state) do
    Logger.warn("[#{module}]: The consumer was unexpectedly cancelled, tag: #{consumer_tag}")
    {:stop, :cancelled, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, %{module: module} = state) do
    Logger.info("[#{module}]: Consumer was cancelled, tag: #{consumer_tag}")
    {:noreply, state}
  end

  @doc false
  @impl GenServer
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
  @impl GenServer
  def terminate(:connection_closed = reason, %{module: module}) do
    # Since connection has been closed no need to clean it up
    Logger.debug("[#{module}]: Terminating consumer, reason: #{inspect(reason)}")
  end

  @doc false
  @impl GenServer
  def terminate(reason, %{module: module, conn: conn, in: in_chan, out: out_chan}) do
    Logger.debug("[#{module}]: Terminating consumer, reason: #{inspect(reason)}")
    Channel.close(in_chan)
    Channel.close(out_chan)
    Connection.close(conn)
  end

  @doc false
  @impl GenServer
  def terminate({{:shutdown, {:server_initiated_close, error_code, reason}}, _}, %{module: module}) do
    Logger.error("[#{module}]: Terminating consumer, error_code: #{inspect(error_code)}, reason: #{inspect(reason)}")
  end

  @doc false
  @impl GenServer
  def terminate(reason, %{module: module}) do
    Logger.error("[#{module}]: Terminating consumer, unexpected reason: #{inspect(reason)}")
  end

  ##############################################################################
  # Helpers
  ##############################################################################

  defp parse_config(config) do
    q_name = Keyword.fetch!(config, :queue)
    {ttl_val, config_no_q_ttl} = Keyword.pop(config, :queue_ttl, nil)
    {mp_val, config_no_q_mp} = Keyword.pop(config_no_q_ttl, :queue_max_priority, nil)

    queue_settings =
      QueueConfiguration.new(
        q_name,
        true,
        ttl_val,
        mp_val
      )

    config_no_q_mp
    |> Keyword.put(:queue, queue_settings)
    |> Keyword.put(:connection, Keyword.get(config, :connection, config[:uri]))
  end

  defp handle_message(payload, attributes, %{module: module} = state, false) do
    start_time = System.monotonic_time()
    message = Message.create(attributes, payload, state)

    emit_message_start_event(start_time, message, module)
    result = apply(module, :handle_message, [message])
    emit_message_stop_event(start_time, message, module)

    result
  end

  defp handle_message(payload, attributes, %{module: module} = state, true) do
    spawn(fn ->
      start_time = System.monotonic_time()
      message = Message.create(attributes, payload, state)

      emit_message_start_event(start_time, message, module)
      result = apply(module, :handle_message, [message])
      emit_message_stop_event(start_time, message, module)

      result
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
    start_time = System.monotonic_time()
    queue = config[:queue]
    exchange = config[:exchange]
    routing_key = config[:routing_key]

    emit_connection_start_event(start_time, module, attempt, queue, exchange, routing_key)

    case Connection.open(config[:connection]) do
      {:ok, conn} ->
        emit_connection_stop_event(start_time, module, attempt, queue, exchange, routing_key)
        Process.monitor(conn.pid)
        Map.put(state, :conn, conn)

      {:error, e} ->
        Logger.error(
          "[#{module}]: Failed to connect to RabbitMQ with settings: " <>
            "#{inspect(strip_key(config, :connection))}, reason #{inspect(e)}"
        )

        emit_connection_error_event(start_time, module, attempt, queue, exchange, routing_key, e)

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
    queue_config = config[:queue]
    queue = QueueConfiguration.name(queue_config)
    exchange = config[:exchange]
    routing_key = config[:routing_key]
    prefetch_count = String.to_integer(config[:prefetch_count])

    deadletter_args = setup_deadletter(chan, config)

    arguments = QueueConfiguration.build_queue_arguments(queue_config, deadletter_args)

    Basic.qos(chan, prefetch_count: prefetch_count)
    Queue.declare(chan, queue, durable: QueueConfiguration.durable(queue_config), arguments: arguments)
    GenRMQ.Binding.bind_exchange_and_queue(chan, exchange, queue, routing_key)

    consumer_tag = apply(module, :consumer_tag, [])
    {:ok, _consumer_tag} = Basic.consume(chan, queue, nil, consumer_tag: consumer_tag)
    state
  end

  defp setup_deadletter(chan, config) do
    case Keyword.get(config, :deadletter, true) do
      true ->
        queue_config = config[:queue]
        queue = QueueConfiguration.name(queue_config)
        exchange = GenRMQ.Binding.exchange_name(config[:exchange])
        dl_queue = config[:deadletter_queue] || "#{queue}_error"
        dl_exchange = config[:deadletter_exchange] || "#{exchange}.deadletter"
        dl_routing_key = config[:deadletter_routing_key] || "#"

        Queue.declare(
          chan,
          dl_queue,
          durable: true,
          arguments: QueueConfiguration.build_ttl_arguments(queue_config, [])
        )

        GenRMQ.Binding.bind_exchange_and_queue(chan, dl_exchange, dl_queue, dl_routing_key)

        [{"x-dead-letter-exchange", :longstr, dl_exchange}] ++
          case dl_routing_key do
            "#" ->
              []

            _ ->
              [{"x-dead-letter-routing-key", :longstr, dl_routing_key}]
          end

      false ->
        []
    end
  end

  defp emit_message_ack_event(message) do
    start_time = System.monotonic_time()
    measurements = %{time: start_time}
    metadata = %{message: message}

    :telemetry.execute([:gen_rmq, :consumer, :message, :ack], measurements, metadata)
  end

  defp emit_message_reject_event(message, requeue) do
    start_time = System.monotonic_time()
    measurements = %{time: start_time}
    metadata = %{message: message, requeue: requeue}

    :telemetry.execute([:gen_rmq, :consumer, :message, :reject], measurements, metadata)
  end

  defp emit_message_start_event(start_time, message, module) do
    measurements = %{time: start_time}
    metadata = %{message: message, module: module}

    :telemetry.execute([:gen_rmq, :consumer, :message, :start], measurements, metadata)
  end

  defp emit_message_stop_event(start_time, message, module) do
    stop_time = System.monotonic_time()
    measurements = %{time: stop_time, duration: stop_time - start_time}
    metadata = %{message: message, module: module}

    :telemetry.execute([:gen_rmq, :consumer, :message, :stop], measurements, metadata)
  end

  defp emit_connection_down_event(module, reason) do
    start_time = System.monotonic_time()
    measurements = %{time: start_time}
    metadata = %{module: module, reason: reason}

    :telemetry.execute([:gen_rmq, :consumer, :connection, :down], measurements, metadata)
  end

  defp emit_connection_start_event(start_time, module, attempt, queue, exchange, routing_key) do
    measurements = %{time: start_time}

    metadata = %{
      module: module,
      attempt: attempt,
      queue: queue,
      exchange: exchange,
      routing_key: routing_key
    }

    :telemetry.execute([:gen_rmq, :consumer, :connection, :start], measurements, metadata)
  end

  defp emit_connection_stop_event(start_time, module, attempt, queue, exchange, routing_key) do
    stop_time = System.monotonic_time()
    measurements = %{time: stop_time, duration: stop_time - start_time}

    metadata = %{
      module: module,
      attempt: attempt,
      queue: queue,
      exchange: exchange,
      routing_key: routing_key
    }

    :telemetry.execute([:gen_rmq, :consumer, :connection, :stop], measurements, metadata)
  end

  defp emit_connection_error_event(start_time, module, attempt, queue, exchange, routing_key, error) do
    stop_time = System.monotonic_time()
    measurements = %{time: stop_time, duration: stop_time - start_time}

    metadata = %{
      module: module,
      attempt: attempt,
      queue: queue,
      exchange: exchange,
      routing_key: routing_key,
      error: error
    }

    :telemetry.execute([:gen_rmq, :consumer, :connection, :error], measurements, metadata)
  end

  defp strip_key(keyword_list, key) do
    keyword_list
    |> Keyword.delete(key)
    |> Keyword.put(key, "[FILTERED]")
  end

  defp linear_delay(attempt), do: :timer.sleep(attempt * 1_000)

  ##############################################################################
  ##############################################################################
  ##############################################################################
end
