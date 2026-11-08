defmodule TigooServer.Repo.Migrations.SeedSequenceRotation do
  use Ecto.Migration

  # Values captured from "ans-test".app_sequence_rotation on 2026-11-08.
  # IDs are allocated locally; generated rotation counts are computed by PostgreSQL.
  def up do
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""

    execute """
    INSERT INTO #{schema}.app_sequence_rotation (
      period,
      consumer_estatimation_monthly_amount,
      consumer_allowed_monthly_amount,
      consumer_avg,
      rotation_step,
      name,
      code,
      prefix,
      fill,
      increment_by,
      current_seq,
      rotation_window_start,
      current_seq_rotation,
      update_on
    ) VALUES (
      NULL,
      2300000,
      250000,
      3500,
      NULL,
      'E32 · Consumo Electrónico',
      'E32',
      'E32',
      10,
      NULL,
      2,
      NULL,
      NULL,
      NULL
    )
    ON CONFLICT (code) DO NOTHING
    """
  end

  def down do
    raise "Seeded rotation rows may have issued identifiers and must be preserved"
  end
end
