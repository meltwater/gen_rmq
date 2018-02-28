defmodule GenAMQP.Publisher do
  @moduledoc """
  A behaviour module for implementing the RabbitMQ publisher
  """

  use GenServer
  use AMQP
  alias Mix.Project

  require Logger

  ##############################################################################
  # GenPublisher callbacks
  ##############################################################################

  @doc """
  Invoked to provide publisher configuration

  ## Return values
  ### Mandatory:

  `uri` - RabbitMQ uri

  `exchange` - the name of the target exchange. If does not exist it will be created

  ### Optional:

  `app_id` - publishing application ID

  ## Examples:
  ```
  def init() do
    [
      exchange: "gen_amqp_exchange",
      uri: "amqp://guest:guest@localhost:5672"
      app_id: :my_app_id
    ]
  end
  ```

  """
  @callback init() :: [
              exchange: String.t(),
              uri: String.t(),
              app_id: Atom.t()
            ]

  ##############################################################################
  # GenPublisher API
  ##############################################################################

  @doc """
  Starts `GenAMQP.Publisher` with given callback module linked to the current
  process

  `module`- callback module implementing `GenAMQP.Publisher` behaviour

  ## Options
   * `:name` - used for name registration

  ## Return values
  If the publisher is successfully created and initialized, this function returns
  `{:ok, pid}`, where `pid` is the PID of the publisher. If a process with the
  specified publisher name already exists, this function returns
  `{:error, {:already_started, pid}}` with the PID of that process.

  ## Examples:
  ```
  GenAMQP.Publisher.start_link(TestPublisher, name: :publisher)
  ```

  """
  @spec start_link(module :: Module.t(), options :: Keyword.t()) :: {:ok, Pid.t()} | {:error, Any.t()}
  def start_link(module, options \\ []) do
    GenServer.start_link(__MODULE__, %{module: module}, options)
  end

  @doc """
  Publishes given message

  `publisher` - name or PID of the publisher

  `message` - raw payload to deliver

  `routing_key` - optional routing key to set for given message

  ## Examples:
  ```
  GenAMQP.Publisher.publish(TestPublisher, "{\"msg\": \"hello\"})
  ```

  """
  @spec publish(publisher :: Atom.t() | Pid.t(), message :: Binary.t(), routing_key :: String.t()) :: :ok
  def publish(publisher, message, routing_key \\ "") do
    GenServer.call(publisher, {:publish, message, routing_key})
  end

  ##############################################################################
  # GenServer callbacks
  ##############################################################################

  @doc false
  def init(%{module: module} = initial_state) do
    config = apply(module, :init, [])

    initial_state
    |> Map.merge(%{config: config})
    |> setup_publisher
  end

  @doc false
  def handle_call({:publish, msg, key}, _from, %{channel: channel, config: config} = state) do
    result = Basic.publish(channel, config[:exchange], key, msg, base_metadata(config))
    {:reply, result, state}
  end

  @doc false
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %{module: module, config: config}) do
    Logger.info("[#{module}]: RabbitMQ connection is down! Reason: #{inspect(reason)}")
    {:ok, state} = setup_publisher(%{module: module, config: config})
    {:noreply, state}
  end

  ##############################################################################
  # Helpers
  ##############################################################################

  defp setup_publisher(%{module: module, config: config} = state) do
    Logger.info("[#{module}]: Setting up publisher connection and configuration")

    {:ok, conn} = connect(state)
    {:ok, channel} = Channel.open(conn)
    Exchange.topic(channel, config[:exchange], durable: true)
    {:ok, %{channel: channel, module: module, config: config}}
  end

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

  defp base_metadata(config) do
    [
      timestamp: DateTime.to_unix(DateTime.utc_now(), :milliseconds),
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
