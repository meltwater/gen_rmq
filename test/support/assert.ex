defmodule GenAmqp.Test.Assert do
  @moduledoc """
  Assert using polling. Stored latest failure exception in an `Agent`.
  """

  require Logger
  alias ExUnit.AssertionError

  def start_link(_args, _opts \\ []) do
    Agent.start_link(fn -> Map.new() end, name: __MODULE__)
  end

  def repeatedly(function, time \\ 5_000, interval \\ 500) do
    task = Task.async(fn -> repeatedly_loop(function, interval) end)

    case Task.yield(task, time) do
      {:ok, _} ->
        true

      _ ->
        error_message =
          function
          |> last_exception
          |> AssertionError.message()

        raise AssertionError,
          expr: function,
          message:
            "Polling condition did not succeed after #{time / 1000.0}s" <>
              ", reason: #{error_message}"
    end
  end

  defp repeatedly_loop(func, interval) do
    func.()
    :ok
  rescue
    e in AssertionError ->
      set_last_exception(func, e)
      :timer.sleep(interval)
      repeatedly_loop(func, interval)
  end

  def last_exception(function) do
    Agent.get(__MODULE__, &Map.get(&1, function))
  end

  defp set_last_exception(function, exception) do
    Agent.update(__MODULE__, &Map.put(&1, function, exception))
  end
end
