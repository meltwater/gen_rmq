defmodule GenRMQ.MessageTask do
  @moduledoc """
  Struct wrapping details of a Task that is executing the configured
  `handle_message` callback

  Defines:
  * `:task` - the Task struct executing the user's `handle_message` callback
  * `:timeout_reference` - the reference to the timeout timer
  * `:message` - the GenRMQ.Message struct that is being processed
  * `:exit_status` - the exist status of the Task
  """

  @enforce_keys [:task, :timeout_reference, :message, :exit_status]
  defstruct [:task, :timeout_reference, :message, :exit_status]

  @doc false
  def create(task, timeout_reference, message) do
    %__MODULE__{
      task: task,
      timeout_reference: timeout_reference,
      message: message,
      exit_status: nil
    }
  end
end
