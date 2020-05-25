defmodule GenRMQ.MessageTask do
  @moduledoc """
  Struct wrapping details of a Task that is executing the configured
  `handle_message` callback

  Defines:
  * `:task` - the Task struct executing the user's `handle_message` callback
  * `:timeout_reference` - the reference to the timeout timer
  * `:message` - the GenRMQ.Message struct that is being processed
  * `:start_time` - the monotonic time that the task was started
  """

  alias __MODULE__

  @enforce_keys [:task, :timeout_reference, :message, :start_time]
  defstruct [:task, :timeout_reference, :message, :start_time]

  @doc false
  def create(task, timeout_reference, message) do
    %MessageTask{
      task: task,
      timeout_reference: timeout_reference,
      message: message,
      start_time: System.monotonic_time()
    }
  end
end
