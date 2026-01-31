defmodule Ricqchet.Repo do
  use Ecto.Repo,
    otp_app: :ricqchet,
    adapter: Ecto.Adapters.Postgres
end
