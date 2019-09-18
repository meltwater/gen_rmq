defmodule GenRMQ.Publisher do
  @moduledoc """
  A behaviour module for implementing the RabbitMQ publisher
  """

  use GenServer
  use AMQP
  alias Mix.Project

  require Logger

  # list of fields permitted in message metadata at top level
  @metadata_fields :P_basic
                   |> Record.extract(from_lib: "rabbit_common/include/rabbit_framing.hrl")
                   |> Keyword.keys()

  ##############################################################################
  # GenRMQ.Publisher callbacks
  ##############################################################################

  @doc """
  Invoked to provide publisher configuration

  ## Return values
  ### Mandatory:

  `uri` - RabbitMQ uri

  `exchange` - the target exchange. If does not exist, it will be created.

  ### Optional:

  `app_id` - publishing application ID

  `activate_confirmations` - activates publishing confirmations on the channel

  `max_confirmation_wait_time` - maximum time in milliseconds to wait for a confirmation. By default it is 5_000 (5s).

  ## Examples:
  ```
  def init() do
    [
      exchange: "gen_rmq_exchange",
      uri: "amqp://guest:guest@localhost:5672"
      app_id: :my_app_id,
      activate_confirmations: true,
      max_confirmation_wait_time: 5_000
    ]
  end
  ```

  """
  @callback init() :: [
              exchange: GenRMQ.Binding.exchange(),
              uri: String.t(),
              app_id: atom,
              activate_confirmations: boolean,
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

  `metadata` - optional metadata to set for given message. Keys that
              are not allowed in metadata are moved under the `:headers`
              field. Do not include a `:headers` field here: it will be
              created automatically with all non-standard keys that you have
              provided.

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
        ) :: :ok | {:error, reason :: :blocked | :closing | :confirmation_timeout}
  def publish(publisher, message, routing_key \\ "", metadata \\ []) do
    GenServer.call(publisher, {:publish, message, routing_key, metadata})
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
    send(self(), :init)
    {:ok, state}
  end

  @doc false
  @impl GenServer
  def handle_call({:publish, msg, key, metadata}, _from, %{channel: channel, config: config} = state) do
    metadata = config |> base_metadata() |> merge_metadata(metadata)
    publish_result = Basic.publish(channel, GenRMQ.Binding.exchange_name(config[:exchange]), key, msg, metadata)
    confirmation_result = wait_for_confirmation(channel, config)
    {:reply, publish_result(publish_result, confirmation_result), state}
  end

  @doc false
  @impl GenServer
  def handle_info(:init, %{module: module, config: config}) do
    Logger.info("[#{module}]: Setting up publisher connection and configuration")
    {:ok, state} = setup_publisher(%{module: module, config: config})
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{module: module, config: config}) do
    Logger.info("[#{module}]: RabbitMQ connection is down! Reason: #{inspect(reason)}")
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

  ##############################################################################
  # Helpers
  ##############################################################################

  defp setup_publisher(%{module: module, config: config} = state) do
    {:ok, conn} = connect(state)
    {:ok, channel} = Channel.open(conn)
    GenRMQ.Binding.declare_exchange(channel, config[:exchange])

    with_confirmations = Keyword.get(config, :activate_confirmations, false)
    :ok = activate_confirmations(channel, with_confirmations)
    {:ok, %{channel: channel, module: module, config: config, conn: conn}}
  end

  defp activate_confirmations(channel, true), do: AMQP.Confirm.select(channel)
  defp activate_confirmations(_, _), do: :ok

  defp wait_for_confirmation(channel, config) do
    with_confirmations = Keyword.get(config, :activate_confirmations, false)
    max_wait_time = config |> Keyword.get(:max_confirmation_wait_time, 5_000)
    wait_for_confirmation(channel, with_confirmations, max_wait_time)
  end

  defp wait_for_confirmation(channel, true, max_wait_time), do: AMQP.Confirm.wait_for_confirms(channel, max_wait_time)
  defp wait_for_confirmation(_, _, _), do: true

  defp publish_result(:ok, true), do: :ok
  defp publish_result(:ok, :timeout), do: {:error, :confirmation_timeout}
  defp publish_result(error, _), do: error

  defp connect(%{module: module, config: config} = state) do
    case Connection.open(config[:uri]) do
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
    # take "standard" fields and put them into metadata top-level
    metadata
    # put default values, override custom values on conflict
    |> Keyword.merge(base)
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
    config[:app_id] || Keyword.get(Project.config(), :app)
  end

  ##############################################################################
  ##############################################################################
  ##############################################################################
end
