defmodule GenRMQ.Consumer do
  @moduledoc """
  A behaviour module for implementing the RabbitMQ consumer.

  It will:
  * setup RabbitMQ connection / channel and keep them in a state
  * create (if does not exist) a queue and bind it to an exchange
  * create deadletter queue and exchange
  * handle reconnections
  * call `handle_message` callback on every message delivery
  * call `handle_error` callback whenever `handle_message` fails to process or times out
  """

  use GenServer
  use AMQP

  require Logger

  alias GenRMQ.Consumer.{
    MessageTask,
    QueueConfiguration,
    Telemetry
  }

  alias GenRMQ.Message

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

  `queue_options` - Queue options as declared in
  [AMQP.Queue.declare/3](https://hexdocs.pm/amqp/AMQP.Queue.html#declare/3).

  If argument 'x-expires' is given to arguments, then it will be used instead
  of `queue_ttl`.

  If argument 'x-max-priority' is given to arguments, then it will be used
  instead of `queue_max_priority`.

  `queue_ttl` - controls for how long a queue can be unused before it is
  automatically deleted. Unused means the queue has no consumers,
  the queue has not been redeclared, and basic.get has not been invoked
  for a duration of at least the expiration period

  `queue_max_priority` - defines if a declared queue should be a priority queue.
  Should be set to a value from `1..255` range. If it is greater than `255`, queue
  max priority will be set to `255`. Values between `1` and `10` are
  [recommended](https://www.rabbitmq.com/priority.html#resource-usage).

  `concurrency` - defines if `handle_message` callback is called
  in separate process using [supervised task](https://hexdocs.pm/elixir/Task.Supervisor.html).
  By default concurrency is enabled. To disable, set it to `false`

  `terminate_timeout` - defines how long the consumer will wait for in-flight Tasks to
  complete before terminating the process. The value is in milliseconds and the default
  is 5_000 milliseconds.

  `handle_message_timeout` - defines how long the `handle_message` callback will execute
  within a supervised task. The value is in milliseconds and the default is 5_000
  milliseconds.

  `retry_delay_function` - custom retry delay function. Called when the connection to
  the broker cannot be established. Receives the connection attempt as an argument (>= 1)
  and is expected to wait for some time.
  With this callback you can for example do exponential backoff.
  The default implementation is a linear delay starting with 1 second step.

  `reconnect` - defines if consumer should reconnect on connection termination.
  By default reconnection is enabled.

  `deadletter` - defines if consumer should setup deadletter exchange and queue.
  (**Default:** `true`).

  `deadletter_queue` - defines name of the deadletter queue (**Default:** Same as queue name suffixed by `_error`).

  `deadletter_queue_options` - Queue options for the deadletter queue as declared in [AMQP.Queue.declare/3](https://hexdocs.pm/amqp/AMQP.Queue.html#declare/3).

  If argument 'x-expires' is given to arguments, then it will be used instead of `queue_ttl`.

  If argument 'x-max-priority' is given to arguments, then it will be used instead of `queue_max_priority`.

  `deadletter_exchange` - defines name of the deadletter exchange (**Default:** Same as exchange name suffixed by `.deadletter`).

  `deadletter_routing_key` - defines name of the deadletter routing key (**Default:** `#`).

  ## Examples:
  ```
  def init() do
    [
      connection: "amqp://guest:guest@localhost:5672",
      queue: "gen_rmq_in_queue",
      queue_options: [
        durable: true,
        passive: true,
        arguments: [
          {"x-queue-type", :longstr ,"quorum"}
        ]
      ]
      exchange: "gen_rmq_exchange",
      routing_key: "#",
      prefetch_count: "10",
      uri: "amqp://guest:guest@localhost:5672",
      concurrency: true,
      terminate_timeout: 5_000,
      handle_message_timeout: 5_000,
      queue_ttl: 5_000,
      retry_delay_function: fn attempt -> :timer.sleep(1000 * attempt) end,
      reconnect: true,
      deadletter: true,
      deadletter_queue: "gen_rmq_in_queue_error",
      deadletter_queue_options: [
        arguments: [
          {"x-queue-type", :longstr ,"quorum"}
        ]
      ]
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
              queue_options: keyword,
              exchange: GenRMQ.Binding.exchange(),
              routing_key: [String.t()] | String.t(),
              prefetch_count: String.t(),
              uri: String.t(),
              concurrency: boolean,
              terminate_timeout: integer,
              handle_message_timeout: integer,
              queue_ttl: integer,
              retry_delay_function: function,
              reconnect: boolean,
              deadletter: boolean,
              deadletter_queue: String.t(),
              deadletter_queue_options: keyword,
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

  @doc """
  Invoked when an error or timeout is encountered while executing `handle_message` callback

  `message` - `GenRMQ.Message` struct
  `reason` - the information regarding the error

  ## Examples:
  To reject the message that caused the Task to fail you can do something like so:
  ```
  def handle_error(message, reason) do
    # Do something with message and reject it
    Logger.warn("Failed to process message: #\{inspect(message)}")

    GenRMQ.Consumer.reject(message)
  end
  ```

  The `reason` argument will either be the atom `:killed` if the Task timed out and needed
  to be stopped. Or it will be a 2 elementr tuple where the first element is the error stuct
  and the second element is the stacktrace:

  ```
  {
    %RuntimeError{message: "Can't divide by zero!"},
    [
      {TestConsumer.ErrorWithoutConcurrency, :handle_message, 1, [file: 'test/support/test_consumers.ex', line: 98]},
      {GenRMQ.Consumer, :handle_message, 2, [file: 'lib/consumer.ex', line: 519]},
      {GenRMQ.Consumer, :handle_info, 2, [file: 'lib/consumer.ex', line: 424]},
      {:gen_server, :try_dispatch, 4, [file: 'gen_server.erl', line: 637]},
      {:gen_server, :handle_msg, 6, [file: 'gen_server.erl', line: 711]},
      {:proc_lib, :init_p_do_apply, 3, [file: 'proc_lib.erl', line: 249]}
    ]
  }
  ```
  """
  @callback handle_error(message :: %GenRMQ.Message{}, reason :: atom()) :: :ok

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
    Telemetry.emit_message_ack_event(message)

    Basic.ack(channel, tag)
  end

  @doc """
  Requeues / rejects given message

  `message` - `GenRMQ.Message` struct

  `requeue` - indicates if message should be requeued
  """
  @spec reject(message :: %GenRMQ.Message{}, requeue :: boolean) :: :ok
  def reject(%Message{state: %{in: channel}, attributes: %{delivery_tag: tag}} = message, requeue \\ false) do
    Telemetry.emit_message_reject_event(message, requeue)

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
    terminate_timeout = Keyword.get(parsed_config, :terminate_timeout, 5_000)
    handle_message_timeout = Keyword.get(parsed_config, :handle_message_timeout, 5_000)

    state =
      initial_state
      |> Map.put(:config, parsed_config)
      |> Map.put(:reconnect_attempt, 0)
      |> Map.put(:running_tasks, %{})
      |> Map.put(:terminate_timeout, terminate_timeout)
      |> Map.put(:handle_message_timeout, handle_message_timeout)

    {:ok, state, {:continue, :init}}
  end

  @doc false
  @impl GenServer
  def handle_continue(:init, state) do
    state =
      state
      |> get_connection()
      |> open_channels()
      |> setup_consumer()
      |> setup_task_supervisor()

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_call({:recover, requeue}, _from, %{in: channel} = state) do
    {:reply, Basic.recover(channel, requeue: requeue), state}
  end

  @doc false
  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{module: module, config: config, running_tasks: running_tasks} = state
      ) do
    case Map.get(running_tasks, ref) do
      %MessageTask{message: message, timeout_reference: timeout_reference, start_time: start_time} ->
        Logger.info("[#{module}]: Task failed to handle message. Reason: #{inspect(reason)}")

        # Cancel timeout timer, emit telemetry event, and invoke user's `handle_error` callback
        Process.cancel_timer(timeout_reference)
        updated_state = %{state | running_tasks: Map.delete(running_tasks, ref)}
        Telemetry.emit_message_error_event(module, reason, message, start_time)
        apply(module, :handle_error, [message, reason])

        {:noreply, updated_state}

      _ ->
        Logger.info("[#{module}]: RabbitMQ connection is down! Reason: #{inspect(reason)}")

        Telemetry.emit_connection_down_event(module, reason)

        config
        |> Keyword.get(:reconnect, true)
        |> handle_reconnect(state)
    end
  end

  @doc false
  @impl GenServer
  def handle_info({ref, _task_result}, %{running_tasks: running_tasks} = state) when is_reference(ref) do
    # Task completed successfully, update the running task map and state
    Process.demonitor(ref, [:flush])

    updated_state =
      case Map.get(running_tasks, ref) do
        %MessageTask{} = message_task ->
          Process.cancel_timer(message_task.timeout_reference)
          %{state | running_tasks: Map.delete(running_tasks, ref)}

        _ ->
          state
      end

    {:noreply, updated_state}
  end

  @doc false
  @impl GenServer
  def handle_info({:kill, task_reference}, %{running_tasks: running_tasks} = state) when is_reference(task_reference) do
    # The task has timed out, kill the Task process which will trigger a :DOWN event that
    # is handled by a previous `handle_info/2` callback
    %MessageTask{task: %Task{pid: pid}} = Map.get(running_tasks, task_reference)
    Process.exit(pid, :kill)

    {:noreply, state}
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
  def handle_info(
        {:basic_deliver, payload, attributes},
        %{module: module, running_tasks: running_tasks, handle_message_timeout: handle_message_timeout} = state
      ) do
    %{delivery_tag: tag, routing_key: routing_key, redelivered: redelivered} = attributes
    Logger.debug("[#{module}]: Received message. Tag: #{tag}, routing key: #{routing_key}, redelivered: #{redelivered}")

    if redelivered do
      Logger.debug("[#{module}]: Redelivered payload for message. Tag: #{tag}, payload: #{payload}")
    end

    message = Message.create(attributes, payload, state)

    updated_state =
      case handle_message(message, state) do
        %Task{ref: task_reference} = task ->
          timeout_reference = Process.send_after(self(), {:kill, task_reference}, handle_message_timeout)
          message_task = MessageTask.create(task, timeout_reference, message)
          %{state | running_tasks: Map.put(running_tasks, task_reference, message_task)}

        _ ->
          state
      end

    {:noreply, updated_state}
  end

  @doc false
  @impl GenServer
  def terminate(:connection_closed = reason, %{module: module} = state) do
    await_running_tasks(state)

    # Since connection has been closed no need to clean it up
    Logger.debug("[#{module}]: Terminating consumer, reason: #{inspect(reason)}")
  end

  @doc false
  @impl GenServer
  def terminate(reason, %{module: module, conn: conn, in: in_chan, out: out_chan} = state) do
    await_running_tasks(state)

    Logger.debug("[#{module}]: Terminating consumer, reason: #{inspect(reason)}")
    Channel.close(in_chan)
    Channel.close(out_chan)
    Connection.close(conn)
  end

  @doc false
  @impl GenServer
  def terminate({{:shutdown, {:server_initiated_close, error_code, reason}}, _}, %{module: module} = state) do
    await_running_tasks(state)

    Logger.error("[#{module}]: Terminating consumer, error_code: #{inspect(error_code)}, reason: #{inspect(reason)}")
  end

  @doc false
  @impl GenServer
  def terminate(reason, %{module: module} = state) do
    await_running_tasks(state)

    Logger.error("[#{module}]: Terminating consumer, unexpected reason: #{inspect(reason)}")
  end

  ##############################################################################
  # Helpers
  ##############################################################################

  defp await_running_tasks(%{running_tasks: running_tasks, terminate_timeout: terminate_timeout}) do
    # Await for all in-flight tasks for the configured amount of time and cancel
    # their individual timeout timers
    running_tasks
    |> Map.values()
    |> Enum.map(fn %MessageTask{} = message_task ->
      Process.cancel_timer(message_task.timeout_reference)
      message_task.task
    end)
    |> Task.yield_many(terminate_timeout)
  end

  defp parse_config(config) do
    queue_name = Keyword.fetch!(config, :queue)

    config
    |> Keyword.put(:queue, QueueConfiguration.setup(queue_name, config))
    |> Keyword.put(:connection, Keyword.get(config, :connection, config[:uri]))
  end

  defp handle_message(message, %{module: module, task_supervisor: task_supervisor_pid})
       when is_pid(task_supervisor_pid) do
    Task.Supervisor.async_nolink(
      task_supervisor_pid,
      fn ->
        start_time = System.monotonic_time()

        Telemetry.emit_message_start_event(start_time, message, module)
        result = apply(module, :handle_message, [message])
        Telemetry.emit_message_stop_event(start_time, message, module)

        result
      end,
      shutdown: :brutal_kill
    )
  end

  defp handle_message(message, %{module: module}) do
    start_time = System.monotonic_time()
    Telemetry.emit_message_start_event(start_time, message, module)

    try do
      result = apply(module, :handle_message, [message])
      Telemetry.emit_message_stop_event(start_time, message, module)

      result
    rescue
      reason ->
        full_error = {reason, __STACKTRACE__}
        Telemetry.emit_message_error_event(module, full_error, message, start_time)
        apply(module, :handle_error, [message, full_error])
        :error
    end
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

    Telemetry.emit_connection_start_event(start_time, module, attempt, queue, exchange, routing_key)

    case Connection.open(config[:connection]) do
      {:ok, conn} ->
        Telemetry.emit_connection_stop_event(start_time, module, attempt, queue, exchange, routing_key)
        Process.monitor(conn.pid)
        Map.put(state, :conn, conn)

      {:error, e} ->
        Logger.error(
          "[#{module}]: Failed to connect to RabbitMQ with settings: " <>
            "#{inspect(strip_key(config, :connection))}, reason #{inspect(e)}"
        )

        Telemetry.emit_connection_error_event(start_time, module, attempt, queue, exchange, routing_key, e)

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

  defp setup_task_supervisor(%{config: config} = state) do
    if Keyword.get(config, :concurrency, true) do
      {:ok, pid} = Task.Supervisor.start_link(max_restarts: 0)

      Map.put(state, :task_supervisor, pid)
    else
      Map.put(state, :task_supervisor, nil)
    end
  end

  defp setup_consumer(%{in: chan, config: config, module: module} = state) do
    queue_config = config[:queue]
    prefetch_count = String.to_integer(config[:prefetch_count])

    if queue_config.dead_letter[:create] do
      setup_deadletter(chan, queue_config.dead_letter)
    end

    Basic.qos(chan, prefetch_count: prefetch_count)
    setup_queue(queue_config.name, queue_config.options, chan, config[:exchange], config[:routing_key])
    consumer_tag = apply(module, :consumer_tag, [])
    {:ok, _consumer_tag} = Basic.consume(chan, queue_config.name, nil, consumer_tag: consumer_tag)
    state
  end

  defp setup_deadletter(chan, config) do
    setup_queue(config[:name], config[:options], chan, config[:exchange], config[:routing_key])
  end

  defp setup_queue(name, options, chan, exchange, routing_key) do
    Queue.declare(chan, name, options)
    GenRMQ.Binding.bind_exchange_and_queue(chan, exchange, name, routing_key)
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
