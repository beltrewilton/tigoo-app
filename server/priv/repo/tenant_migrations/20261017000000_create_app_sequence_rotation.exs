defmodule PosServer.Repo.Migrations.CreateAppSequenceRotation do
  use Ecto.Migration

  def change do
    create table(:app_sequence_rotation, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :period, :date
      add :consumer_estatimation_monthly_amount, :decimal
      add :consumer_allowed_monthly_amount, :decimal
      add :consumer_avg, :decimal

      # NULLIF leaves the result NULL when a divisor is zero.
      add :rotation_available, :decimal,
        generated:
          "ALWAYS AS (round(consumer_allowed_monthly_amount / NULLIF(consumer_avg, 0))) STORED"

      # PostgreSQL generated columns cannot reference another generated column.
      add :rotation_allowed_steps, :decimal,
        generated: """
        ALWAYS AS (
          round(
            round(consumer_estatimation_monthly_amount / NULLIF(consumer_avg, 0)) /
            NULLIF(round(consumer_allowed_monthly_amount / NULLIF(consumer_avg, 0)), 0)
          )
        ) STORED
        """

      add :rotation_step, :decimal
      add :name, :string
      add :code, :string, null: false
      add :prefix, :string
      add :fill, :integer
      add :increment_by, :integer
      add :current_seq, :bigint
      add :rotation_window_start, :bigint
      add :current_seq_rotation, :bigint
      add :update_on, :naive_datetime
    end

    create unique_index(:app_sequence_rotation, [:code])
  end
end
