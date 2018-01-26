defmodule GenAMQP.Publisher do
  @moduledoc """
  Defines generic behaviour for AMQP publisher.
  """

  use GenServer
  use AMQP
  alias Mix.Project

  require Logger

  ##############################################################################
  # GenPublisher callbacks
  ##############################################################################

  @doc "Should provide publisher config"
  @callback init(Any.t()) :: Keyword.t()

  ##############################################################################
  # GenPublisher API
  ##############################################################################

  @doc "Starts amqp publisher"
  def start_link(module, opts \\ []) do
    GenServer.start_link(__MODULE__, %{module: module}, opts)
  end

  @doc "Publishes message for given publisher"
  def publish(publisher, message, routing_key \\ "#") do
    GenServer.call(publisher, {:publish, message, routing_key})
  end

  ##############################################################################
  # GenServer callbacks
  ##############################################################################

  def init(%{module: module} = initial_state) do
    config = apply(module, :init, [[]])

    initial_state
    |> Map.merge(%{config: config})
    |> setup_publisher
  end

  def handle_call({:publish, msg, key}, _from, %{channel: channel, config: config} = state) do
    result = Basic.publish(channel, config[:exchange], key, msg, base_metadata())
    {:reply, result, state}
  end

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

  defp base_metadata do
    [
      timestamp: DateTime.to_unix(DateTime.utc_now(), :milliseconds),
      app_id: Project.config() |> Keyword.get(:app) |> Atom.to_string(),
      content_type: "application/json"
    ]
  end

  ##############################################################################
  ##############################################################################
  ##############################################################################
end
