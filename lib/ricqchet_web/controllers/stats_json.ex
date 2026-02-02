defmodule RicqchetWeb.StatsJSON do
  @moduledoc """
  JSON views for stats controller responses.
  """

  def messages(%{stats: stats}) do
    stats
  end

  def message_sizes(%{stats: stats}) do
    stats
  end

  def delivery(%{stats: stats}) do
    stats
  end

  def errors(%{stats: stats}) do
    stats
  end

  def destinations(%{stats: stats}) do
    stats
  end

  def activity(%{stats: stats}) do
    stats
  end
end
