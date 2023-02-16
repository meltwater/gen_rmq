defmodule GenRMQ.Publisher do
  @moduledoc """
  A behaviour module for implementing the RabbitMQ publisher
  """

  use GenServer
  use AMQP

  require Logger

  alias GenRMQ.Publisher.Telemetry
  alias GenRMQ.Queue

  # list of fields permitted in message metadata at top level
  @metadata_fields ~w(
    mandatory
    immediate
    content_type
    content_encoding
    persistent
    priority
    correlation_id
    reply_to
    expiration
    message_id
    timestamp
    type
    user_id
    app_id
    cluster_id
  )a

  ##############################################################################
  # GenRMQ.Publisher callbacks
  ##############################################################################

  @doc """
  Invoked to provide publisher configuration

  ## Return values
  ### Mandatory:

  `connection` - RabbitMQ connection options. Accepts same arguments as AMQP-library's [Connection.open/2](https://hexdocs.pm/amqp/AMQP.Connection.html#open/2).

  `exchange` - name, `:default` or `{type, name}` or `{type, name, durable}` of the target exchange.
  If it does not exist, it will be created. Supported types: `:direct`, `:fanout`, `:topic`

  ### Optional:

  `uri` - RabbitMQ uri. Deprecated. Please use `connection`.

  `app_id` - publishing application ID. By default it is `:gen_rmq`.

  `enable_confirmations` - activates publishing confirmations on the channel. Confirmations are disabled by default.

  `max_confirmation_wait_time` - maximum time in milliseconds to wait for a confirmation. By default it is 5_000 (5s).

  ## Examples:
  ```
  def init() do
    [
      exchange: "gen_rmq_exchange",
      connection: "amqp://guest:guest@localhost:5672",
      uri: "amqp://guest:guest@localhost:5672",
      app_id: :my_app_id,
      enable_confirmations: true,
      max_confirmation_wait_time: 5_000
    ]
  end
  ```

  """
  @callback init() :: [
              connection: keyword | {String.t(), String.t()} | :undefined | keyword,
              exchange: GenRMQ.Binding.exchange(),
              uri: String.t(),
              app_id: atom,
              enable_confirmations: boolean,
              max_confirmation_wait_time: integer
            ]

  ##############################################################################
  # GenRMQ.Publisher API
  ##############################################################################

  @doc """
  Starts `GenRMQ.Publisher` with given callback module linked to the current
  process

  `module`- callback module implementing `GenRMQ.Publisher` behaviour

  ## Options
   * `:name` - used for name registration

  ## Return values
  If the publisher is successfully created and initialized, this function returns
  `{:ok, pid}`, where `pid` is the PID of the publisher. If a process with the
  specified publisher name already exists, this function returns
  `{:error, {:already_started, pid}}` with the PID of that process.

  ## Examples:
  ```
  GenRMQ.Publisher.start_link(TestPublisher, name: :publisher)
  ```

  """
  @spec start_link(module :: module(), options :: Keyword.t()) :: {:ok, pid} | {:error, term}
  def start_link(module, options \\ []) do
    GenServer.start_link(__MODULE__, %{module: module}, options)
  end

  @doc """
  Publishes given message

  `publisher` - name or PID of the publisher

  `message` - raw payload to deliver

  `routing_key` - optional routing key to set for given message

  `metadata` - optional metadata to set for given message. Keys that \
              are not allowed in metadata are moved under the `:headers` \
              field. Do not include a `:headers` field here: it will be \
              created automatically with all non-standard keys that you have \
              provided. For a full list of options see `AMQP.Basic.publish/5`

  ## Examples:
  ```
  GenRMQ.Publisher.publish(TestPublisher, "{\"msg\": \"hello\"})
  ```

  """
  @spec publish(
          publisher :: atom | pid,
          message :: String.t(),
          routing_key :: String.t(),
          metadata :: Keyword.t()
        ) :: :ok | {:ok, :confirmed} | {:error, reason :: :blocked | :closing | :confirmation_timeout}
  def publish(publisher, message, routing_key \\ "", metadata \\ []) do
    GenServer.call(publisher, {:publish, message, routing_key, metadata})
  end

  @doc """
  Get the number of active consumers on the provided queue. If a nonexistent
  queue is provided, an error will be raised.

  `publisher` - name or PID of the publisher

  `queue` - name of the queue
  """
  @spec consumer_count(publisher :: atom | pid, queue :: String.t()) :: integer() | no_return()
  def consumer_count(publisher, queue) do
    GenServer.call(publisher, {:consumer_count, queue})
  end

  @doc """
  Return whether the provided queue is empty or not. If a nonexistent
  queue is provided, an error will be raised.

  `publisher` - name or PID of the publisher

  `queue` - name of the queue
  """
  @spec empty?(publisher :: atom | pid, queue :: String.t()) :: boolean() | no_return()
  def empty?(publisher, queue) do
    GenServer.call(publisher, {:empty?, queue})
  end

  @doc """
  Get the number of messages currently ready for delivery in the provided queue.
  If a nonexistent queue is provided, an error will be raised.

  `publisher` - name or PID of the publisher

  `queue` - name of the queue
  """
  @spec message_count(publisher :: atom | pid, queue :: String.t()) :: integer() | no_return()
  def message_count(publisher, queue) do
    GenServer.call(publisher, {:message_count, queue})
  end

  @doc """
  Drop all message from the provided queue. If a nonexistent
  queue is provided, an error will be raised.

  `publisher` - name or PID of the publisher

  `queue` - name of the queue
  """
  @spec purge(publisher :: atom | pid, queue :: String.t()) :: {:ok, map} | Basic.error()
  def purge(publisher, queue) do
    GenServer.call(publisher, {:purge, queue})
  end

  @doc """
  Get the message count and consumer count for a particular queue. If a nonexistent
  queue is provided, an error will be raised.

  `publisher` - name or PID of the publisher

  `queue` - name of the queue
  """
  @spec status(publisher :: atom | pid, queue :: String.t()) :: {:ok, map} | Basic.error()
  def status(publisher, queue) do
    GenServer.call(publisher, {:status, queue})
  end

  ##############################################################################
  # GenServer callbacks
  ##############################################################################

  @doc false
  @impl GenServer
  def init(%{module: module} = initial_state) do
    Process.flag(:trap_exit, true)
    config = apply(module, :init, [])
    state = Map.merge(initial_state, %{config: config})

    {:ok, state, {:continue, :init}}
  end

  @doc false
  @impl GenServer
  def handle_continue(:init, %{module: module, config: config}) do
    Logger.info("[#{module}]: Setting up publisher connection and configuration")
    {:ok, state} = setup_publisher(%{module: module, config: config})

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_call({:publish, msg, key, metadata}, _from, %{channel: channel, config: config} = state) do
    metadata = config |> base_metadata() |> merge_metadata(metadata)
    start_time = System.monotonic_time()
    exchange = config[:exchange]

    Telemetry.emit_publish_start_event(exchange, msg)

    publish_result = Basic.publish(channel, GenRMQ.Binding.exchange_name(exchange), key, msg, metadata)

    case publish_result do
      :ok -> Telemetry.emit_publish_stop_event(start_time, exchange, msg)
      {_kind, error} -> Telemetry.emit_publish_stop_event(start_time, exchange, msg, error)
    end

    confirmation_result = wait_for_confirmation(channel, config)

    {:reply, publish_result(publish_result, confirmation_result), state}
  end

  @doc false
  @impl GenServer
  def handle_call({:consumer_count, queue}, _from, %{channel: channel} = state) do
    result = Queue.consumer_count(channel, queue)

    {:reply, result, state}
  end

  @doc false
  @impl GenServer
  def handle_call({:empty?, queue}, _from, %{channel: channel} = state) do
    result = Queue.empty?(channel, queue)

    {:reply, result, state}
  end

  @doc false
  @impl GenServer
  def handle_call({:message_count, queue}, _from, %{channel: channel} = state) do
    result = Queue.message_count(channel, queue)

    {:reply, result, state}
  end

  @doc false
  @impl GenServer
  def handle_call({:purge, queue}, _from, %{channel: channel} = state) do
    result = Queue.purge(channel, queue)

    {:reply, result, state}
  end

  @doc false
  @impl GenServer
  def handle_call({:status, queue}, _from, %{channel: channel} = state) do
    result = Queue.status(channel, queue)

    {:reply, result, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{module: module, config: config}) do
    Logger.info("[#{module}]: RabbitMQ connection is down! Reason: #{inspect(reason)}")

    Telemetry.emit_connection_down_event(module, reason)

    {:ok, state} = setup_publisher(%{module: module, config: config})
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def terminate(reason, %{module: module, conn: conn, channel: channel}) do
    Logger.debug("[#{module}]: Terminating publisher, reason: #{inspect(reason)}")
    Channel.close(channel)
    Connection.close(conn)
  end

  @doc false
  @impl GenServer
  def terminate({{:shutdown, {:server_initiated_close, error_code, reason}}, _}, %{module: module}) do
    Logger.error("[#{module}]: Terminating publisher, error_code: #{inspect(error_code)}, reason: #{inspect(reason)}")
  end

  @doc false
  @impl GenServer
  def terminate(reason, %{module: module}) do
    Logger.error("[#{module}]: Terminating publisher, unexpected reason: #{inspect(reason)}")
  end

  ##############################################################################
  # Helpers
  ##############################################################################

  defp setup_publisher(%{module: module, config: config} = state) do
    state = Map.put(state, :config, parse_config(config))
    start_time = System.monotonic_time()
    exchange = config[:exchange]

    Telemetry.emit_connection_start_event(exchange)

    {:ok, conn} = connect(state)
    {:ok, channel} = Channel.open(conn)
    GenRMQ.Binding.declare_exchange(channel, exchange)

    with_confirmations = Keyword.get(config, :enable_confirmations, false)
    :ok = activate_confirmations(channel, with_confirmations)

    Telemetry.emit_connection_stop_event(start_time, exchange)

    {:ok, %{channel: channel, module: module, config: config, conn: conn}}
  end

  defp parse_config(config) do
    # Backwards compatibility support
    # Use connection-keyword if it's set, otherwise use uri-keyword
    Keyword.put(config, :connection, Keyword.get(config, :connection, config[:uri]))
  end

  defp activate_confirmations(_, false), do: :ok
  defp activate_confirmations(channel, true), do: AMQP.Confirm.select(channel)

  defp wait_for_confirmation(channel, config) do
    with_confirmations = Keyword.get(config, :enable_confirmations, false)
    max_wait_time = config |> Keyword.get(:max_confirmation_wait_time, 5_000)
    wait_for_confirmation(channel, with_confirmations, max_wait_time)
  end

  defp wait_for_confirmation(_, false, _), do: :confirmation_disabled
  defp wait_for_confirmation(channel, true, max_wait_time), do: AMQP.Confirm.wait_for_confirms(channel, max_wait_time)

  defp publish_result(:ok, :confirmation_disabled), do: :ok
  defp publish_result(:ok, true = _confirmed), do: {:ok, :confirmed}
  defp publish_result(:ok, :timeout), do: {:error, :confirmation_timeout}
  defp publish_result(error, _), do: error

  defp connect(%{module: module, config: config} = state) do
    case Connection.open(config[:connection]) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        {:ok, conn}

      {:error, e} ->
        Logger.error("[#{module}]: Failed to connect to RabbitMQ, reason: #{inspect(e)}")
        :timer.sleep(5000)
        connect(state)
    end
  end

  # Put standard metadata fields to top level, everything else into headers
  defp merge_metadata(base, custom) do
    {metadata, headers} = custom |> Keyword.split(@metadata_fields)
    # take "base" fields and put them into metadata top-level
    base
    # put custom values, override base values on conflict
    |> Keyword.merge(metadata)
    # put all custom fields in the headers
    |> Keyword.merge(headers: headers)
  end

  defp base_metadata(config) do
    [
      timestamp: DateTime.to_unix(DateTime.utc_now(), :millisecond),
      app_id: config |> app_id() |> Atom.to_string(),
      content_type: "application/json"
    ]
  end

  defp app_id(config) do
    config[:app_id] || :gen_rmq
  end

  ##############################################################################
  ##############################################################################
  ##############################################################################
end
